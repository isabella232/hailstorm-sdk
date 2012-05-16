# Database schema for Hailstorm, creates all the necessary tables.
# @author Sayantam Dey

require 'hailstorm/support'

class Hailstorm::Support::Schema
  
  # List of tables in schema  
  SchemaTables = [
    :projects,
    :amazon_clouds,
    :jmeter_plans,
    :load_agents,
    :target_hosts,
    :clusters,
    :execution_cycles,
    :client_stats,
    :page_stats,
    :target_stats
  ].freeze

  
  def self.create_schema()
    schema = self.new
    schema.create()
  end
  
  # Creates the application schema in the application db directory.
  # A sqlite3 database is created. The database name is <tt>#{Hailstorm.app_name}.sqlite3</tt>.
  # If the tables already exist, nothing is changed.
  def create()
     
    SchemaTables.each do |t|
      create_table(t)
    end
  end
  
  def create_table(table_name)
      
    unless ActiveRecord::Base.connection.table_exists?(table_name)
      logger.debug("Creating #{table_name} table...")
      self.send("create_#{table_name}")
    end
  end
  
  def create_projects
    ActiveRecord::Migration.create_table(:projects) do |t|
      t.string  :project_code, :null => false
      t.integer :max_threads_per_agent, :null => false, :default => 50
      t.boolean :master_slave_mode, :null => false, :default => true
      t.string  :samples_breakup_interval, :null => false, :default => '1,3,5'
      t.string  :serial_version, :default => nil
    end
  end
  
  def create_amazon_clouds
    ActiveRecord::Migration.create_table(:amazon_clouds) do |t|
      t.references  :project, :null => false
      t.string      :access_key, :null => false
      t.string      :secret_key, :null => false
      t.string      :ssh_identity, :null => false
      t.string      :region, :null => false
      t.string      :zone, :null => false
      t.string      :agent_ami, :default => nil
      t.boolean     :active, :null => false, :default => false
      t.string      :user_name, :null => false, :default => 'ubuntu'
      t.string      :security_group, :null => false
    end
  end
  
  def create_jmeter_plans
    ActiveRecord::Migration.create_table(:jmeter_plans) do |t|
      t.references  :project, :null => false
      t.string      :test_plan_name, :null => false  
      t.string      :content_hash, :null => false
      t.boolean     :active, :null => false, :default => false
      t.text        :properties, :default => nil
      t.integer     :latest_threads_count, :default => nil
    end    
  end
  
  def create_load_agents
    ActiveRecord::Migration.create_table(:load_agents) do |t|
      t.integer     :clusterable_id, :null => false
      t.string      :clusterable_type, :null => false
      t.references  :jmeter_plan, :null => false
      t.string      :public_ip_address, :default => nil
      t.string      :private_ip_address, :default => nil
      t.boolean     :active, :null => false, :default => true
      t.string      :type, :null => false
      t.integer     :jmeter_pid, :default => nil
      t.string      :identifier, :default => nil
    end
  end

  def create_target_hosts
    ActiveRecord::Migration.create_table(:target_hosts) do |t|
      t.string      :host_name, :null => false
      t.references  :project, :null => false
      t.string      :type, :null => false
      t.string      :role_name, :null => false
      t.string      :executable_path, :default => nil
      t.integer     :executable_pid, :default => nil
      t.string      :ssh_identity, :default => nil
      t.string      :user_name, :default => nil
      t.integer     :sampling_interval, :null => false, :default => 10
      t.boolean     :active, :null => false, :default => false  
    end
  end
  
  def create_clusters
    ActiveRecord::Migration.create_table(:clusters) do |t|
      t.references  :project, :null => false
      t.string      :cluster_type, :null => false
    end
  end
  
  def create_execution_cycles
    ActiveRecord::Migration.create_table(:execution_cycles) do |t|
      t.references  :project, :null => false
      t.string      :status, :null => false, :default => "started"
      t.timestamp   :started_at, :null => false
      t.timestamp   :stopped_at, :default => nil
    end
  end
  
  def create_client_stats
    ActiveRecord::Migration.create_table(:client_stats) do |t|
      t.references  :execution_cycle, :null => false
      t.references  :jmeter_plan, :null => false
      t.integer     :clusterable_id, :null => false
      t.string      :clusterable_type, :null => false
      t.integer     :threads_count, :null => false
      t.float       :aggregate_ninety_percentile, :default => nil
      t.float       :aggregate_response_throughput, :default => nil
      t.timestamp   :last_sample_at, :default => nil
    end
  end

  def create_page_stats
    ActiveRecord::Migration.create_table(:page_stats) do |t|
      t.references  :client_stat, :null => false
      t.string      :page_label, :null => false
      t.integer     :samples_count, :null => false
      t.float       :average_response_time, :null => false
      t.float       :median_response_time, :null => false
      t.float       :ninety_percentile_response_time, :null => false
      t.float       :minimum_response_time, :null => false
      t.float       :maximum_response_time, :null => false
      t.decimal     :percentage_errors, :precision => 5, :scale => 2, :null => false
      t.float       :response_throughput, :null => false
      t.float       :size_throughput, :null => false
      t.float       :standard_deviation, :null => false
      t.string      :samples_breakup_json, :null => false, :default => '{}'
    end
  end

  def create_target_stats
    ActiveRecord::Migration.create_table(:target_stats) do |t|
      t.references  :execution_cycle, :null => false
      t.references  :target_host, :null => false
      t.float       :average_cpu_usage, :null => false
      t.float       :average_memory_usage, :null => false
      t.float       :average_swap_usage, :default => nil
      t.binary      :cpu_usage_trend, :default => nil
      t.binary      :memory_usage_trend, :default => nil
      t.binary      :swap_usage_trend, :default => nil
    end
  end
  
end
