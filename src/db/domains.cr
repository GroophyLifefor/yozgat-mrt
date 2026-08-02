module Yozgat
  module DB
    module Domains
      alias Row = NamedTuple(domainName: String, port: Int64)

      def self.list(project_id : Int64, environment_id : Int64) : Array(Row)
        rows = [] of Row
        Yozgat::DB.database.query(
          "SELECT domain_name, port FROM domains WHERE project_id = ?1 AND environment_id = ?2 ORDER BY id",
          project_id, environment_id,
        ) do |rs|
          rs.each { rows << {domainName: rs.read(String), port: rs.read(Int64)} }
        end
        rows
      end
    end
  end
end
