import Foundation
import Dispatch

#if (os(macOS) || os(iOS))
    import Darwin
    fileprivate let sockConnect = Darwin.connect
#else
    import Glibc
    fileprivate let sockConnect = connect
#endif

public class TCPClient : TCPSocket {
    /// A buffer, specific to this client
    let incomingBuffer = Buffer()
    
    public init(hostname: String, port: UInt16, onRead: @escaping ReadCallback) throws {
        self.onRead = onRead
        
        try super.init(hostname: hostname, port: port)
    }
    
    public func connect() throws {
        try self.connect(startReading: true)
    }
    
    internal func connect(startReading: Bool = true) throws {
        if startReading {
            self.readSource.setEventHandler(qos: .userInteractive) {
                let read = recv(self.descriptor, self.incomingBuffer.pointer, Int(UInt16.max), 0)
                
                guard read != 0 else {
                    self.readSource.cancel()
                    return
                }
                
                self.onRead(self.incomingBuffer.pointer, read)
            }
            
            self.readSource.setCancelHandler {
                self.close()
            }
        }
        
        let addr =  UnsafeMutablePointer<sockaddr>(OpaquePointer(self.server))
        let addrSize = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        var result: Int32
        
        repeat {
            result = sockConnect(self.descriptor, addr, addrSize)
        } while result == -1 && (errno == EINPROGRESS || errno == EALREADY)
        
        if result == -1 {
            guard errno == EINPROGRESS || errno == EISCONN else {
                throw TCPError.unableToConnect
            }
        }
        
        if startReading {
            self.readSource.resume()
        }
    }
    
    open func close() {
        Darwin.close(self.descriptor)
    }
    
    var onRead: ReadCallback
    
    deinit {
        readSource.cancel()
    }
}
