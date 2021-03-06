#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

/// A constant to be used for parsing
fileprivate let multipartContentType = [UInt8]("multipart/form-data; boundary=".utf8)

extension Request {
    /// Parses the request's body into a `MultipartForm`
    public var multipart: MultipartForm? {
        if let boundary = self.headers["Content-Type"] {
            guard memcmp(boundary.bytes, multipartContentType, multipartContentType.count) == 0 ,boundary.bytes.count > multipartContentType.count &+ 2 else {
                return nil
            }
            
            return MultipartForm(
                boundary: Array(boundary.bytes[multipartContentType.count..<boundary.bytes.count]),
                bodyFrom: self)
        }
        
        return nil
    }
}

/// Hardcoded constant for parsing
fileprivate let contentDispositionMark = [UInt8]("Content-Disposition: ".utf8)

/// Hardcoded constant for parsing
fileprivate let formData = [UInt8]("form-data;".utf8)

/// Hardcoded constant for parsing
fileprivate let attachment = [UInt8]("attachment;".utf8)

/// A parsed Multipart Form
public final class MultipartForm {
    /// The parsed parts
    public var parts: [Part]
    public let boundary: [UInt8]
    
    /// A single Multipart pair
    ///
    /// Contains a key and value
    public struct Part {
        /// A multipart value type
        public enum PartType {
            /// A string value
            case value
            case file(mime: String, name: String)
        }
        
        public let name: String?
        public let type: PartType
        public let data: BodyRepresentable
        
        /// Parses the String value associated with this part, if possible/reasonable
        public var string: String? {
            guard case .value = type, let body = try? data.makeBody() else {
                return nil
            }
            
            return String(bytes: body.buffer, encoding: .utf8)
        }
    }
    
    public func append(_ file: File) {
        let part = Part(name: file.name, type: .file(mime: file.mimeType, name: file.name), data: file)
        self.parts.append(part)
    }
    
    public func append(file body: BodyRepresentable, named name: String, MIME: String) {
        let part = Part(name: nil, type: .file(mime: MIME, name: name), data: body)
        self.parts.append(part)
    }
    
    let strongReference: AnyObject?
    
    /// Accesses a Part at the provided key, if there is any
    public subscript(_ key: String) -> MultipartForm.Part? {
        for part in parts where part.name == key {
            return part
        }
        
        return nil
    }
    
    public init(boundary: String, parts: [Part] = []) {
        self.boundary = [UInt8](boundary.utf8)
        self.parts = parts
        self.strongReference = nil
    }
    
    /// Creates a new multipart form
    init?(boundary: [UInt8], bodyFrom request: Request) {
        self.boundary = boundary
        self.strongReference = request
        
        guard let buffer = request.body else {
            return nil
        }
        
        guard var base = UnsafePointer(buffer.buffer.baseAddress) else {
            return nil
        }
        
        var currentPosition = 0
        var length = buffer.buffer.count
        var parts = [Part]()
        
        // Iterate over all key-value pairs
        while boundary.count &+ 4 < length {
            // '--' before each boundary
            guard base[0] == 0x2d, base[1] == 0x2d else {
                return nil
            }
            
            base = base.advanced(by: 2)
            
            // Double-check the boundary
            guard memcmp(base, boundary, boundary.count) == 0 else {
                return nil
            }
            
            // The boundary must be succeeded by `\r\n` for additional elements
            guard base[boundary.count] == 0x0d, base[boundary.count &+ 1] == 0x0a else {
                // '--' can be there when you reach end of the multipart form
                guard base[boundary.count] == 0x2d, base[boundary.count &+ 1] == 0x2d else {
                    return nil
                }
                
                self.parts = parts
                return
            }
            
            // scan for the end of the key
            length = length &- boundary.count
            base = base.advanced(by: boundary.count &+ 2)
            
            // Check for "Content-Disposition"
            guard contentDispositionMark.count < length, memcmp(base, contentDispositionMark, contentDispositionMark.count) == 0 else {
                return nil
            }
            
            length = length &- contentDispositionMark.count
            base = base.advanced(by: contentDispositionMark.count)
            
            // ' ', the space inbetween a key and value in the header
            base.peek(until: 0x20, length: &length, offset: &currentPosition)
            
            guard currentPosition > 0 else {
                return nil
            }
            
            let contentDisposition = base.buffer(until: &currentPosition)
            
            // If the value is a normal FormData
            if formData.count &+ 1 < length, contentDisposition.count == formData.count, let address = contentDisposition.baseAddress, memcmp(address, formData, formData.count) == 0 {
                // ' ' Scan past the header, for the name
                guard contentDisposition.baseAddress?[contentDisposition.count] == 0x20 else {
                    return nil
                }
                
                // '"' scan for the start of the name
                base.peek(until: 0x22, length: &length, offset: &currentPosition)
                
                guard currentPosition > 1 else {
                    return nil
                }
                
                // '"' Scan for the end of the name
                base.peek(until: 0x22, length: &length, offset: &currentPosition)
                
                // Take the name of the field
                let nameBuffer = base.buffer(until: &currentPosition)
                
                guard let name = String(bytes: nameBuffer, encoding: .utf8) else {
                    return nil
                }
                
                guard 6 < length else {
                    return nil
                }
                
                func readContentsBuffer() -> UnsafeMutableBufferPointer<UInt8>? {
                    // Keep track of the content length
                    var total = 0
                    
                    repeat {
                        // Scan until the end of the value
                        base.peek(until: 0x0d, length: &length, offset: &currentPosition)
                        total = total &+ currentPosition
                        
                        // `\r\n` at the end of a value
                        // start of next boundary, after `\r\n`
                    } while length >= 4 &+ boundary.count && !(
                        base[-1] == 0x0d && base[0] == 0x0a && base[1] == 0x2d &&
                            base[2] == 0x2d && memcmp(base.advanced(by: 3), boundary, boundary.count) == 0)
                    
                    guard length > boundary.count &+ 4 else {
                        return nil
                    }
                    
                    // Point to the stored data
                    let dataBuffer = base.buffer(until: &total)
                    
                    guard let baseAddress = dataBuffer.baseAddress else {
                        return nil
                    }
                    
                    let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: dataBuffer.count)
                    bufferPointer.assign(from: baseAddress, count: dataBuffer.count)
                    
                    // skip \n
                    base = base.advanced(by: 1)
                    
                    return UnsafeMutableBufferPointer(start: bufferPointer, count: dataBuffer.count)
                }
                
                // Returns success without throwing
                func readValue() -> Bool {
                    // Skip 4 bytes, the "\r\n\r\n"
                    length = length &- 4
                    base = base.advanced(by: 4)
                    
                    guard let buffer = readContentsBuffer() else {
                        return false
                    }
                    
                    // Append the part
                    parts.append(Part(name: name, type: .value, data: Body(pointingTo: buffer, deallocating: true)))
                    return true
                }
                
                func readFile() -> Bool {
                    func parseHeaders() -> Headers {
                        let start = base
                        
                        while true {
                            // \n
                            base.peek(until: 0x0a, length: &length, offset: &currentPosition)
                            
                            guard currentPosition > 0 else {
                                return Headers()
                            }
                            
                            if length > 1, base[-2] == 0x0d, base[0] == 0x0d, base[1] == 0x0a {
                                defer {
                                    base = base.advanced(by: 2)
                                    length = length &- 2
                                }
                                
                                return Headers(serialized: UnsafeBufferPointer(start: start, count: start.distance(to: base)))
                            }
                        }
                    }
                    
                    // '"' scan for the start of the file name
                    base.peek(until: 0x22, length: &length, offset: &currentPosition)
                    
                    guard currentPosition > 1 else {
                        return false
                    }
                    
                    // '"' Scan for the end of the file name
                    base.peek(until: 0x22, length: &length, offset: &currentPosition)
                    
                    let filenameBuffer = base.buffer(until: &currentPosition)
                    
                    guard let filename = String(bytes: filenameBuffer, encoding: .utf8) else {
                        return false
                    }
                    
                    let headers = parseHeaders()
                    
                    let type = String(headers["Content-Type"]) ?? "*/*"
                    
                    guard let buffer = readContentsBuffer() else {
                        return false
                    }
                    
                    // Append the part
                    parts.append(Part(name: name, type: .file(mime: type, name: filename), data: Body(pointingTo: buffer, deallocating: true)))
                    return true
                }
                
                // `\r\n\r\n` after the name, to start the value
                if base[0] == 0x0d, base[1] == 0x0a, base[2] == 0x0d, base[3] == 0x0a {
                    guard readValue() else {
                        return nil
                    }
                    // '; filename="'
                } else if base[0] == 0x3b {
                    guard readFile() else {
                        return nil
                    }
                }
            } else {
                // unsupported
                return nil
            }
        }
        
        self.parts = parts
    }
    
//    public func write(_ writer: ((UnsafeBufferPointer<UInt8>) throws -> ())) throws {
//        let buffer = Buffer(capacity: Int(UInt16.max))
//        let fullBoundary = [0x2d, 0x2d] + boundary
//        var offset = 0
//
//        func write(_ data: [UInt8]) {
//            memcpy(buffer.pointer.advanced(by: offset), data, data.count)
//            offset += data.count
//        }
//
//        func writeString(_ string: String) {
//            write([UInt8](string.utf8))
//        }
//
//        func writeBoundary() {
//            write(fullBoundary + [0x0d, 0x0a])
//        }
//
//        for part in parts {
//            writeBoundary()
//
//            if case .mime(let mime) = part.type {
//                writeString("Content-Type: \(mime); charset=utf8\r\n\r\n")
//            }
//
//            part.data
//        }
//    }
//
//    public func makeBody() throws -> Body {
//        fatalError()
//    }
}

// MARK - Copy for swift inline optimization

extension UnsafePointer where Pointee == UInt8 {
    fileprivate func buffer(until length: inout Int) -> UnsafeBufferPointer<UInt8> {
        guard length > 0 else {
            return UnsafeBufferPointer<UInt8>(start: nil, count: 0)
        }
        
        // - 1 for the skipped byte
        return UnsafeBufferPointer(start: self.advanced(by: -length), count: length &- 1)
    }
    
    fileprivate mutating func peek(until byte: UInt8, length: inout Int, offset: inout Int) {
        offset = 0
        defer { length = length &- offset }
        
        while offset &+ 4 < length {
            if self[0] == byte {
                offset = offset &+ 1
                self = self.advanced(by: 1)
                return
            }
            if self[1] == byte {
                offset = offset &+ 2
                self = self.advanced(by: 2)
                return
            }
            if self[2] == byte {
                offset = offset &+ 3
                self = self.advanced(by: 3)
                return
            }
            offset = offset &+ 4
            defer { self = self.advanced(by: 4) }
            if self[3] == byte {
                return
            }
        }
        
        if offset < length, self[0] == byte {
            offset = offset &+ 1
            self = self.advanced(by: 1)
            return
        }
        if offset &+ 1 < length, self[1] == byte {
            offset = offset &+ 2
            self = self.advanced(by: 2)
            return
        }
        if offset &+ 2 < length, self[2] == byte {
            offset = offset &+ 3
            self = self.advanced(by: 3)
            return
        }
        
        self = self.advanced(by: length &- offset)
        offset = length
    }
}
