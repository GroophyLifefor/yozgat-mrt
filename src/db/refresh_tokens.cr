module Yozgat
  module DB
    module RefreshTokens
      REFRESH_TTL = "+30 days"

      alias ActiveRow = NamedTuple(
        id: Int64,
        user_id: Int64,
        email: String,
        role: String,
      )

      def self.insert(user_id : Int64, token_hash : String, user_agent : String?) : Nil
        Yozgat::DB.database.exec(
          "INSERT INTO refresh_tokens (user_id, token_hash, expires_at, user_agent)
           VALUES (?, ?, datetime('now', ?), ?)",
          user_id,
          token_hash,
          REFRESH_TTL,
          user_agent,
        )
      end

      def self.find_active(token_hash : String) : ActiveRow?
        Yozgat::DB.database.query_one?(
          "SELECT rt.id, rt.user_id, u.email, u.role
           FROM refresh_tokens rt
           INNER JOIN users u ON u.id = rt.user_id
           WHERE rt.token_hash = ?
             AND rt.revoked_at IS NULL
             AND datetime(rt.expires_at) > datetime('now')",
          token_hash,
        ) do |rs|
          {
            id:      rs.read(Int64),
            user_id: rs.read(Int64),
            email:   rs.read(String),
            role:    rs.read(String),
          }
        end
      end

      # Rotates a refresh token inside an open transaction. Returns the new row id.
      def self.rotate!(
        tx : ::DB::Transaction,
        old_id : Int64,
        user_id : Int64,
        new_hash : String,
        user_agent : String?,
      ) : Int64
        tx.connection.exec(
          "INSERT INTO refresh_tokens (user_id, token_hash, expires_at, user_agent)
           VALUES (?, ?, datetime('now', ?), ?)",
          user_id,
          new_hash,
          REFRESH_TTL,
          user_agent,
        )
        new_id = tx.connection.query_one("SELECT last_insert_rowid()", as: Int64)

        n = tx.connection.exec(
          "UPDATE refresh_tokens
           SET revoked_at = datetime('now'), replaced_by = ?
           WHERE id = ? AND revoked_at IS NULL",
          new_id,
          old_id,
        ).rows_affected

        raise "refresh token concurrency conflict" unless n == 1
        new_id
      end

      def self.revoke_by_hash(token_hash : String) : Nil
        Yozgat::DB.database.exec(
          "UPDATE refresh_tokens
           SET revoked_at = datetime('now')
           WHERE token_hash = ? AND revoked_at IS NULL",
          token_hash,
        )
      end

      def self.revoke_all_for_user(user_id : Int64) : Nil
        Yozgat::DB.database.exec(
          "UPDATE refresh_tokens
           SET revoked_at = datetime('now')
           WHERE user_id = ? AND revoked_at IS NULL",
          user_id,
        )
      end
    end
  end
end
