# status enum
#   :waiting
#   :started
#   :failed
#   :success
#
#   ???
#   :profit!
#
module Juici
  class Build
    # A wrapper around the build process

    include Mongoid::Document
    include ::Juici.url_helpers("builds")
    include BuildLogic
    # TODO Builds should probably be children of projects in the URL?

    field :parent, type: String
    field :command, type: String
    field :environment, type: Hash
    field :create_time, type: Time, :default => Proc.new { Time.now }
    field :start_time, type: Time, :default => nil
    field :end_time, type: Time, :default => nil
    field :status, type: Symbol, :default => :waiting
    field :priority, type: Fixnum, :default => 1
    field :pid, type: Fixnum
    field :buffer, type: String
    field :warnings, type: Array, :default => []
    field :callbacks, type: Array, :default => []

    def set_status(value)
      self[:status] = value
      save!
    end

    def start!
      self[:start_time] = Time.now
      set_status :started
    end

    def success!
      finish
      set_status :success
      process_callbacks
    end

    def failure!
      finish
      set_status :failed
      process_callbacks
    end

    def finish
      self[:end_time] = Time.now
      self[:output] = get_output
      $build_queue.purge(:pid, self)
    end

    def build!
      case pid = spawn_build
      when Fixnum
        start!
        Juici.dbgp "#{pid} away!"
        self[:pid] = pid
        self[:buffer] = @buffer.path
        save!
        return pid
      when :enoent
        warn! "No such command"
        failure!
      when :invalidcommand
        warn! "Invalid command"
        failure!
      end
      nil
    end

    def worktree
      File.join(Config.workspace, parent)
    end

    # View helpers
    def heading_color
      case status
      when :waiting
        "build-heading-pending"
      when :failed
        "build-heading-failed"
      when :success
        "build-heading-success"
      when :started
        "build-heading-started"
      end
    end

    def get_output
      return "" unless self[:buffer]
      File.open(self[:buffer], 'r') do |f|
        f.rewind
        f.read
      end
    end

    def warn!(msg)
      warnings << msg
      save!
    end

    def process_callbacks
      self[:callbacks].each do |callback_url|
        Callback.new(self, callback_url).process!
      end
    end


    def to_form_hash
      {
        "project" => self[:parent],
        "status" => self[:status],
        "url" => ""
      }
    end

  end
end
