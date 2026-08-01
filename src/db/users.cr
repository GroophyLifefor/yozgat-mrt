module Yozgat
  module DB
    alias UserRow = NamedTuple(
      id: Int64,
      email: String,
      password_hash: String,
      role: String,
      created_at: String,
    )

    SELECT_USER_COLUMNS = "id, email, password_hash, role, created_at"

    def self.count_users : Int64
      database.query_one("SELECT COUNT(*) FROM users", as: Int64)
    end

    def self.find_user_by_email(email : String) : UserRow?
      database.query_one?(
        "SELECT #{SELECT_USER_COLUMNS} FROM users WHERE email = ?1 COLLATE NOCASE",
        email,
      ) do |rs|
        read_user(rs)
      end
    end

    def self.find_user_by_id(id : Int64) : UserRow?
      database.query_one?(
        "SELECT #{SELECT_USER_COLUMNS} FROM users WHERE id = ?1",
        id,
      ) do |rs|
        read_user(rs)
      end
    end

    # Inserts the first (admin) user atomically. Returns the new id, or nil if
    # a user already exists (the WHERE NOT EXISTS guard makes it race-free).
    def self.create_admin(email : String, password_hash : String) : Int64?
      result = database.exec(
        "INSERT INTO users (email, password_hash, role)
         SELECT ?, ?, 'admin'
         WHERE NOT EXISTS (SELECT 1 FROM users)",
        email,
        password_hash,
      )
      result.rows_affected == 1 ? result.last_insert_id : nil
    end

    private def self.read_user(rs : ::DB::ResultSet) : UserRow
      {
        id:            rs.read(Int64),
        email:         rs.read(String),
        password_hash: rs.read(String),
        role:          rs.read(String),
        created_at:    rs.read(String),
      }
    end
  end
end
