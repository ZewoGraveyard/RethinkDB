public struct ReqlConfig {
    let host: String
    let port: Int
    let db: String
    let username: String
    let password: String
    let timeout: Int

    init(host: String = "127.0.0.1",
         port: Int = 28015,
         db: String = "test",
         username: String = "admin",
         password: String = "",
         timeout: Int = 20) {
        self.host = host
        self.port = port
        self.db = db
        self.username = username
        self.password = password
        self.timeout = timeout
    }
}
