/// An HTTP Request method
///
/// Used to provide information about the kind of action being requested
public enum Method : Equatable, Hashable, Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        let string = try container.decode(String.self).uppercased()
        
        switch string {
        case "GET": self = .get
        case "PUT": self = .put
        case "POST": self = .post
        case "PATCH": self = .patch
        case "DELETE": self = .delete
        case "OPTIONS": self = .options
        default: self = .other(string)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .get: try container.encode("GET")
        case .put: try container.encode("PUT")
        case .post: try container.encode("POST")
        case .delete: try container.encode("DELETE")
        case .patch: try container.encode("PATCH")
        case .options: try container.encode("OPTIONS")
        case .other(let method): try container.encode(method)
        }
    }
    
    /// A GET request is used to retrieve information, such as a web-page or profile picture
    ///
    /// GET Requests will not provide a body
    case get
    
    /// PUT is used to overwrite information.
    ///
    /// `PUT /users/1` is should replace the information for the user with ID `1`
    ///
    /// It may create a new entity if the requested entity didn't exist.
    case put
    
    /// POST is used to create a new entity, such as a reaction in the comment section
    ///
    /// One of the more common methods, since it's also used to create new users and log in existing users
    case post
    
    /// DELETE is an action that... deletes an entity.
    ///
    /// DELETE requests cannot provide a body
    case delete
    
    /// PATCH is similar to PUT in that it updates an entity.
    ///
    /// ..but where PUT replaces an entity, PATCH only updated the specified fields
    case patch
    
    /// OPTIONS is used by the browser to check if the conditions allow a specific request.
    ///
    /// Often used for secutity purposes.
    case options
    
    /// There are many other methods. But the other ones are most commonly used.
    ///
    /// This `.other` contains the provided METHOD
    case other(String)
    
    public var hashValue: Int {
        switch self {
        case .get: return 2000
        case .put: return 2001
        case .post: return 2002
        case .delete: return 2003
        case .patch: return 2004
        case .options: return 2005
        case .other(let s):  return 2006 &+ s.hashValue
        }
    }
    
    public static func ==(lhs: Method, rhs: Method) -> Bool {
        switch (lhs, rhs) {
        case (.get, .get): return true
        case (.put, .put): return true
        case (.post, .post): return true
        case (.delete, .delete): return true
        case (.patch, .patch): return true
        case (.options, .options): return true
        case (.other(let lhsString), .other(let rhsString)): return lhsString == rhsString
        default: return false
        }
    }
}

/// Class so you don't copy the data at all and treat them like a state machine
open class Request : Encodable {
    public let method: Method
    public var url: Path
    public let headers: Headers
    public let body: Body?
    
    /// Creates a new request
    init(with method: Method, url: Path, headers: Headers, body: UnsafeMutableBufferPointer<UInt8>?, deallocating: Bool = false) {
        self.method = method
        self.url = url
        self.headers = headers
        
        if let body = body {
            self.body = Body(pointingTo: body, deallocating: deallocating)
        } else {
            self.body = nil
        }
    }
}


