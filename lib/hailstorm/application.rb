# CLI application (default) for Hailstorm. This handles the application directory
# structure creation (via the hailstorm executable) and also implements the
# command processor (shell) invoked by the script/hailstorm executable.

# @author Sayantam Dey

require 'readline'
require 'terminal-table'

require 'hailstorm'
require 'hailstorm/exceptions'
require 'hailstorm/support/configuration'
require 'hailstorm/support/schema'
require 'hailstorm/support/thread'
require 'hailstorm/model/project'

require 'hailstorm/model/nmon'

class Hailstorm::Application
  

  # Initialize the application and connects to the database
  # @param [String] app_name the application name
  # @param [String] boot_file_path full path to application config/boot.rb
  # @return nil
  def self.initialize!(app_name, boot_file_path)
    
    Hailstorm.app_name = app_name
    Hailstorm.root = File.expand_path("../..", boot_file_path)
    # set JAVA classpath
    # Add config/log4j.xml if it exists
    custom_log4j = File.join(Hailstorm.root, Hailstorm.config_dir, 'log4j.xml')
    if File.exists?(custom_log4j)
      $CLASSPATH << custom_log4j
    end
    # Add all Java Jars to classpath
    java_lib = File.expand_path('../java/lib', __FILE__)
    $CLASSPATH << java_lib
    Dir[File.join(java_lib, '*.jar')].each do |jar|
      require(jar)
    end
    java.lang.System.setProperty("hailstorm.log.dir",
                                 File.join(Hailstorm.root, Hailstorm.log_dir))

    Hailstorm.application = self.new
    Hailstorm.application.load_config(true)
    Hailstorm.application.check_database()
  end

  # Constructor
  def initialize
    @multi_threaded = true
    @exit_command_counter = 0
    ActiveRecord::Base.logger = logger
  end

  # Initializes the application - creates directory structure and support files
  def create_project(invocation_path, arg_app_name)

    root_path = File.join(invocation_path, arg_app_name)
    FileUtils.mkpath(root_path)
    puts "(in #{invocation_path})"
    puts "  created directory: #{arg_app_name}"
    create_app_structure(root_path, arg_app_name)
    puts ""
    puts "Done!"
  end

  # Processes the user commands and options
  def process_commands

    logger.debug { ["\n", '*' * 80, "Application started at #{Time.now.to_s}", '-' * 80].join("\n") }
    # reload commands from saved history if such file exists
    reload_saved_history()

    puts "Welcome to the Hailstorm shell. Type help to get started..."
    trap("INT", proc { logger.warn("Type [quit|exit|ctrl+D] to exit shell") } )

    # for IRB like shell, save state for later execution
    shell_binding = FreeShell.new.get_binding()

    while @exit_command_counter >= 0

      command = Readline.readline("hs > ", true)

      # process EOF (Control+D)
      if command.nil?
        unless exit_ok?
          @exit_command_counter += 1
          logger.warn {"You have running load agents: terminate first or quit/exit explicitly"}
        else
          puts "Bye"
          @exit_command_counter = -1
        end
      end

      # skip empty lines
      if command.blank?
        Readline::HISTORY.pop
        next
      end
      command.chomp!
      command.strip!

      begin
        interpret_command(command)

      rescue IncorrectCommandException => incorrect_command
        puts incorrect_command.message()

      rescue UnknownCommandException
        unless Hailstorm.env == :production
          # execute the command as-is like IRB
          begin
            out = shell_binding.eval(command)
            print '=> '
            if out.nil? or not out.is_a?(String)
              print out.inspect
            else
              print out
            end
            puts ''
          rescue Exception => irb_exception
            puts "[#{irb_exception.class.name}]: #{irb_exception.message}"
            logger.debug { "\n".concat(irb_exception.backtrace.join("\n")) }
          end
        else
          logger.error {"Unknown command: #{command}"}
        end

      rescue Hailstorm::Exception => hailstorm_exception
        logger.error hailstorm_exception.message()

      rescue Hailstorm::Error => hailstorm_error
        logger.error hailstorm_error.cause.message()
        logger.debug { "\n".concat(hailstorm_error.cause.backtrace.join("\n")) }

      rescue StandardError => uncaught
        logger.error uncaught.message
        logger.debug { "\n".concat(uncaught.backtrace.join("\n")) }
      ensure
        ActiveRecord::Base.clear_all_connections!
      end

      save_history(command)
    end
    puts ""
    logger.debug { ["\n", '-' * 80, "Application ended at #{Time.now.to_s}", '*' * 80].join("\n") }
  end

  def multi_threaded?
    @multi_threaded
  end

  def config(&block)

    @config ||= Hailstorm::Support::Configuration.new
    if block_given?
      yield @config
    else
      return @config
    end
  end

  def check_database()

    fail_once = false
    begin
      ActiveRecord::Base.establish_connection(connection_spec) # this is lazy, does not fail!
      # check if the database exists, create it otherwise - this will fail if database does not exist
      ActiveRecord::Base.connection.execute("SELECT count(id) from projects")
    rescue ActiveRecord::ActiveRecordError => e
      unless fail_once
        logger.info "Database does not exist, creating..."
        # database does not exist yet
        create_database()

        # create/update the schema
        Hailstorm::Support::Schema.create_schema()

        fail_once = true
        retry
      else
        logger.error e.message()
        raise
      end
    ensure
      ActiveRecord::Base.clear_all_connections!
    end
  end

  def load_config(handle_load_error = false)

    begin
      @config = nil
      load(File.join(Hailstorm.root, Hailstorm.config_dir, 'environment.rb'))
      @config.freeze()
    rescue Object => e
      if handle_load_error
        logger.fatal(e.message())
      else
        raise(Hailstorm::Exception, e.message())
      end
    end
  end
  alias :reload :load_config

  private
  
  # single point for executing all commands, for exception handling.
  def execute(&block)
    
    begin
      yield
    rescue Hailstorm::Exception
      raise
    rescue StandardError => e
      error = Hailstorm::Error.new
      error.cause = e
      raise(error, e.message())
    end
  end
  
  def current_project
    Hailstorm::Model::Project.where(:project_code => Hailstorm.app_name)
                             .first_or_create!()
  end

  def database_name()
    Hailstorm.app_name
  end

  def create_database()

    ActiveRecord::Base.establish_connection(connection_spec.merge(:database => nil))
    ActiveRecord::Base.connection.create_database(connection_spec[:database])
    ActiveRecord::Base.establish_connection(connection_spec)
  end

  def connection_spec

    if @connection_spec.nil?
      @connection_spec = {}

      # load the properties into a java.util.Properties instance
      database_properties_file = java.io.File.new(File.join(Hailstorm.root,
                                                            Hailstorm.config_dir,
                                                            "database.properties"))
      properties = java.util.Properties.new()
      properties.load(java.io.FileInputStream.new(database_properties_file))

      # load all properties without an empty value into the spec
      properties.each do |key, value|
        unless value.blank?
          @connection_spec[key.to_sym] = value
        end
      end

      # switch off multithread mode for sqlite & derby
      if @connection_spec[:adapter] =~ /(?:sqlite|derby)/i
        @multi_threaded = false
        @connection_spec[:database] = File.join(Hailstorm.root, Hailstorm.db_dir,
                                      "#{database_name}.db")
      else
        # set defaults which can be overridden
        @connection_spec = {
            :pool => 50,
            :wait_timeout => 30.minutes
        }.merge(@connection_spec).merge(:database => database_name)
      end
    end

    return @connection_spec
  end

  # Creates the application directory structure and adds files at appropriate
  # directories
  # @param [String] root_path the path this application will be rooted at
  # @param [String] arg_app_name the argument provided for creating project
  def create_app_structure(root_path, arg_app_name)

    # create directory structure
    dirs = [
      Hailstorm.db_dir,
      Hailstorm.app_dir,
      Hailstorm.log_dir,
      Hailstorm.tmp_dir,
      Hailstorm.reports_dir,
      Hailstorm.config_dir,
      Hailstorm.vendor_dir,
      Hailstorm.script_dir
    ]

    dirs.each do |dir|
      FileUtils.mkpath(File.join(root_path, dir))
      puts "    created directory: #{File.join(arg_app_name, dir)}"
    end

    skeleton_path = File.join(Hailstorm.templates_path, 'skeleton')

    # Copy to Gemfile
    FileUtils.copy(File.join(skeleton_path, 'Gemfile.erb'),
                   File.join(root_path, 'Gemfile'))
    puts "    wrote #{File.join(arg_app_name, 'Gemfile')}"

    # Copy to script/hailstorm
    hailstorm_script = File.join(root_path, Hailstorm.script_dir, 'hailstorm')
    FileUtils.copy(File.join(skeleton_path, 'hailstorm'), hailstorm_script)
    FileUtils.chmod(0775, hailstorm_script) # make it executable
    puts "    wrote #{File.join(arg_app_name, Hailstorm.script_dir, 'hailstorm')}"

    # Copy to config/environment.rb
    FileUtils.copy(File.join(skeleton_path, 'environment.rb'),
                   File.join(root_path, Hailstorm.config_dir))
    puts "    wrote #{File.join(arg_app_name, Hailstorm.config_dir, 'environment.rb')}"

    # Copy to config/database.properties
    FileUtils.copy(File.join(skeleton_path, 'database.properties'),
                   File.join(root_path, Hailstorm.config_dir))
    puts "    wrote #{File.join(arg_app_name, Hailstorm.config_dir, 'database.properties')}"

    # Process to config/boot.rb
    engine = ActionView::Base.new()
    engine.assign(:app_name => arg_app_name)
    File.open(File.join(root_path, Hailstorm.config_dir, 'boot.rb'), 'w') do |f|
      f.print(engine.render(:file => File.join(skeleton_path, 'boot')))
    end

    puts "    wrote #{File.join(arg_app_name, Hailstorm.config_dir, 'boot.rb')}"
  end

  # Sets up the load agents and targets.
  # Creates the load agents as needed and pushes the Jmeter scripts to the agents.
  # Pushes the monitoring artifacts to targets.
  def setup(*args)

    # load/reload the configuration
    execute do
      force = (args.empty? ? false : true)
      current_project.setup(force)

      # output
      show_jmeter_plans()
      show_load_agents()
      show_target_hosts()
    end
  end

  # Starts the load generation and monitoring on targets
  def start(*args)

    execute do
      logger.info("Starting load generation and monitoring on targets...")
      redeploy = (args.empty? ? false : true)
      current_project.start(redeploy)

      show_load_agents()
      show_target_hosts()
    end
  end

  # Stops the load generation and monitoring on targets and collects all logs
  def stop(*args)

    execute do
      logger.info("Stopping load generation and monitoring on targets...")
      wait = args.include?('wait')
      options = (args.include?('suspend') ? {:suspend => true} : nil)
      current_project.stop(wait, options)

      show_load_agents()
      show_target_hosts()
    end
  end

  def abort(*args)

    execute do
      logger.info("Aborting load generation and monitoring on targets...")
      options = (args.include?('suspend') ? {:suspend => true} : nil)
      current_project.abort(options)

      show_load_agents()
      show_target_hosts()
    end
  end

  def terminate(*args)

    execute do
      logger.info("Terminating test cycle...")
      current_project.terminate()

      show_load_agents()
      show_target_hosts()
    end
  end

  def results(*args)

    execute do
      operation = (args.first || 'show').to_sym
      sequences = args[1]
      unless sequences.nil?
        if sequences.match(/^(\d+)\-(\d+)$/)
          sequences = ($1..$2).to_a.collect(&:to_i)
        else
          sequences = sequences.split(/\s*,\s*/).collect(&:to_i)
        end
      end
      rval = current_project.results(operation, sequences)
      if :show == operation
        text_table = Terminal::Table.new()
        text_table.headings = ['Sequence', 'Started', 'Stopped', 'Threads']
        text_table.rows = rval.collect do |execution_cycle|
          [
              execution_cycle.id,
              execution_cycle.formatted_started_at,
              execution_cycle.formatted_stopped_at,
              execution_cycle.total_threads_count
          ]
        end
        puts text_table.to_s
      end
    end
  end

  # Implements the purge commands as per options
  def purge(*args)

    option = args.first || :tests
    case option.to_sym
      when :tests
        current_project.execution_cycles.each {|e| e.destroy()}
        logger.info "Purged all data for tests"
      else
        current_project.destroy()
        logger.info "Purged all project data"
    end
  end

  def show(*args)

    what = (args.first || 'all').to_sym
    show_jmeter_plans() if [:jmeter, :all].include?(what)
    show_load_agents()  if [:cluster, :all].include?(what)
    show_target_hosts() if [:monitor, :all].include?(what)
  end

  def status(*args)

    unless current_project.current_execution_cycle.nil?
      running_agents = current_project.check_status()
      unless running_agents.empty?
        logger.info "Load generation running on following load agents:"
        text_table = Terminal::Table.new()
        text_table.headings = ['Cluster', 'Agent', 'PID']
        text_table.rows = running_agents.collect {|agent|
          [agent.clusterable.slug, agent.public_ip_address, agent.jmeter_pid]
        }
        puts text_table.to_s
      else
        logger.info "Load generation finished on all load agents"
      end
    else
      logger.info "No tests have been started"
    end
  end

  # Process the help command
  def help(*args)

    help_on = args.first || :help
    print self.send("#{help_on}_options")
  end

  # Checks if there are no unterminated load_agents.
  # @return [Boolean] true if there are no unterminated load_agents
  def exit_ok?
    current_project.load_agents().empty?
  end

  # Interpret the command (parse & execute)
  # @param [String] command
  def interpret_command(command)

    if [:exit, :quit].include?(command.to_sym)
      if @exit_command_counter == 0 and !exit_ok?
        @exit_command_counter += 1
        logger.warn {"You have running load agents: terminate first or #{command} again"}
      else
        puts "Bye"
        @exit_command_counter = -1 # "express" exit
      end

    else
      @exit_command_counter = 0 # reset exit intention
      match_data = nil
      grammar().each do |rule|
        match_data = rule.match(command)
        break unless match_data.nil?
      end

      unless match_data.nil?
        method_name = match_data[1].to_sym()
        method_args = match_data.to_a
                                .slice(2, match_data.length - 1)
                                .compact()
                                .collect(&:strip)
        # defer to application for further processing
        self.send(method_name, *method_args)
      else
        raise(UnknownCommandException, "#{command} is unknown")
      end
    end
  end

  # Defines the grammar for the rules
  def grammar()

    @grammar ||= [
        Regexp.new('^(help)(\s+setup|\s+start|\s+stop|\s+abort|\s+terminate|\s+results|\s+purge|\s+show|\s+status)?$'),
        Regexp.new('^(setup)(\s+force)?$'),
        Regexp.new('^(start)(\s+redeploy)?$'),
        Regexp.new('^(stop)(\s+suspend|\s+wait|\s+suspend\s+wait|\s+wait\s+suspend)?$'),
        Regexp.new('^(abort)(\s+suspend)?$'),
        Regexp.new('^(results)(\s+show|\s+exclude|\s+include|\s+report)?(\s+[\d,\-]+)?$'),
        Regexp.new('^(purge)(\s+tests|\s+all)?$'),
        Regexp.new('^(show)(\s+jmeter|\s+cluster|\s+monitor|\s+all)?$'),
        Regexp.new('^(terminate)$'),
        Regexp.new('^(status)$')
    ]
  end

  def save_history(command)

    unless File.exists?(saved_history_path)
      FileUtils.touch(saved_history_path)
    end

    command_history = []
    command_history_size = (ENV['HAILSTORM_HISTORY_LINES'] || 1000).to_i
    File.open(saved_history_path, 'r') do |f|
      f.each_line {|l| command_history.push(l.chomp) unless l.blank? }
    end
    if command_history.size == command_history_size
      command_history.shift()
    end
    if command_history.empty? or command_history.last != command
      command_history.push(command.chomp)
      if command_history.size == 1000
        File.open(saved_history_path, 'w') do |f|
          command_history.each {|c| f.puts(c)}
        end
      else
        File.open(saved_history_path, 'a') do |f|
          f.puts(command)
        end
      end
    end
  end

  def reload_saved_history()

    if File.exists?(saved_history_path)
      File.open(saved_history_path, 'r') do |f|
        f.each_line {|l| Readline::HISTORY.push(l.chomp) }
      end
    end
  end

  def saved_history_path()
    File.join(java.lang.System.getProperty('user.home'), '.hailstorm_history')
  end

  def show_jmeter_plans()
    jmeter_plans = []
    current_project.jmeter_plans.active.each do |jmeter_plan|
      plan = OpenStruct.new
      plan.name = jmeter_plan.test_plan_name
      plan.properties = jmeter_plan.properties_map()
      jmeter_plans.push(plan)
    end
    render_view('jmeter_plan', :jmeter_plans => jmeter_plans)
  end

  def show_load_agents()

    clustered_load_agents = []
    current_project.clusters.each do |cluster|
      cluster.clusterables.each do |clusterable|
        view_item = OpenStruct.new()
        view_item.clusterable_slug = clusterable.slug()
        view_item.terminal_table = Terminal::Table.new()
        view_item.terminal_table.headings = ['JMeter Plan', 'Type', 'IP Address', 'JMeter PID']
        clusterable.load_agents.active.each do |load_agent|
          view_item.terminal_table.add_row([
           load_agent.jmeter_plan.test_plan_name,
           (load_agent.master? ? 'Master' : 'Slave'),
           load_agent.public_ip_address,
           load_agent.jmeter_pid
          ])
        end
        clustered_load_agents.push(view_item)
      end
    end
    render_view('cluster', :clustered_load_agents => clustered_load_agents)
  end

  def show_target_hosts()

    terminal_table = Terminal::Table.new()
    terminal_table.headings = ['Role', 'Host', 'Monitor', 'PID']
    active_target_hosts = current_project.target_hosts()
                                         .active()
                                         .natural_order()
    active_target_hosts.each do |target_host|
      terminal_table.add_row([
                                 target_host.role_name,
                                 target_host.host_name,
                                 target_host.class.name.demodulize.tableize.singularize,
                                 target_host.executable_pid,
                             ])
    end
    render_view('monitor', :terminal_table => terminal_table)
  end

  def render_view(template_file, context_vars = {})

    template_path = File.join(Hailstorm.templates_path, "cli")
    template_file_path = File.join(template_path, template_file)

    engine = ActionView::Base.new()
    engine.view_paths.push(template_path)
    engine.assign(context_vars)
    puts engine.render(:file => template_file_path, :formats => [:text], :handlers => [:erb])
  end


  def help_options()
    @help_options ||=<<-HELP

    Hailstorm shell accepts commands and associated options for a command.

    Commands:

    setup           Boot up load agents and setup target monitors.

    start           Starts load generation and target monitoring.

    stop            Stops load generation and target monitoring.

    abort           Aborts load generation and target monitoring.

    terminate       Terminates load generation and target monitoring.

    results         Operate on results to include, exclude or generate report

    purge           Purge specific or ALL data from database

    show            Show the environment configuration

    status          Show status of load generation across all agents

    help COMMAND    Show help on COMMAND
    HELP
  end

  def setup_options()

    @setup_options ||=<<-SETUP

    Boot load agents and target monitors.
    Creates the load generation agents, sets up the monitors on the configured
    targets and deploys the JMeter scripts in the project app folder to the
    load agents. This task should only be executed after the config
    task is executed.

Options

    force         Force application setup, even when no environment changes
                  are detected.
    SETUP
  end

  def start_options()

    @start_options ||=<<-START

    Starts load generation and target monitoring. This will automatically trigger
    setup actions if you have modified the configuration. Additionally, if any
    JMeter plan is altered, the altered plans will be re-processed. However, modified
    datafiles and other support files (such as custom plugins) will not be re-deployed
    unless the redeploy option is specified.

Options

    redeploy      Re-deploy ALL JMeter scripts and support files to agents.
    START
  end

  def stop_options()

    @stop_options ||=<<-STOP

    Stops load generation and target monitoring.
    Fetch logs from the load agents and server. This does NOT terminate the load
    agents.

Options

    wait          Wait till JMeter completes.
    suspend       Suspend load agents (depends on cluster support).
    STOP
  end

  def abort_options

    @abort_options ||=<<-ABORT

    Aborts load generation and target monitoring.
    This does not fetch logs from the servers and does not terminate the
    load agents. This task is handy when you want to stop the current test
    because you probably realized there was a misconfiguration after starting
    the tests.

Options

    suspend       Suspend load agents (depends on cluster support).
    ABORT
  end

  def terminate_options

    @terminate_options ||=<<-TERMINATE

    Terminates load generation and target monitoring.
    Additionally, cleans up temporary state information on local filesystem.
    You should usually invoke this task at the end of your test run - although
    the system will allow you to execute this task at any point in your testing
    cycle. This also terminates the load agents.
    TERMINATE
  end

  def results_options

    @results_options ||=<<-RESULTS

    Show, include, exclude or generate report for one or more tests. Without any
    options, all successfully stopped tests are displayed. All options accept an
    optional SEQUENCE, which can be a single sequence ID or a comma separated list
    of sequence IDs(4,7) or a hyphen separated list(1-3). The hyphen separated list
    is equivalent to explicity mentioning all IDs in comma separated form.

Options

      show    [SEQUENCE]  Displays successfully stopped tests (default).
      exclude [SEQUENCE]  Exclude SEQUENCE tests.
                          Without a sequence, all tests will be excluded.
      include [SEQUENCE]  Include SEQUENCE tests.
                          Without a sequence, all tests will be included.
      report  [SEQUENCE]  Generate report for sequence.
                          Without a sequence, all succefully stopped tests will
                          be reported.
    RESULTS
  end

  def show_options()

    @show_options ||=<<-SHOW

    Show how the environment is currently configured. Without any option,
    it will show the current configuration for all the environment components.

Options

    jmeter        Show jmeter configuration
    cluster       Show cluster configuration
    monitor       Show monitor configuration
    all           Show load generation status (default)
    SHOW
  end

  def purge_options()

    @purge_options ||=<<-PURGE

    Purge  (remove) all or specific data from the database. You can invoke this
    commmand anytime you want to start over from scratch or remove data for old
    tests. If executed without any options, will only remove data for tests.

    WARNING: The data removed will be unrecoverable!

Options

    tests         Purge the data for all tests (default)
    all           Purge all data
    PURGE
  end

  def status_options()

    @status_options ||=<<-STATUS

    Show the current state of load generation across all agents. If load generation
    is currently executing on any agent, such agents are displayed.
    STATUS
  end


  class UnknownCommandException < Hailstorm::Exception
  end

  class IncorrectCommandException < Hailstorm::Exception
  end

  class FreeShell

    def get_binding()
      binding()
    end
  end

end
