require 'fog'
require 'knife-cloudformation/utils'

Dir.glob(File.join(File.dirname(__FILE__), 'aws_commons/*.rb')).each do |item|
  require "knife-cloudformation/aws_commons/#{File.basename(item).sub('.rb', '')}"
end

module KnifeCloudformation
  class AwsCommons

    FOG_MAP = {
      :ec2 => :compute
    }

    def initialize(args={})
      @ui = args[:ui]
      @creds = args[:fog]
      @connections = {}
      @memo = {
        :stacks => {},
        :event_ids => [],
        :stack_list => {}
      }
    end

    def build_connection(type)
      type = type.to_sym
      type = FOG_MAP[type] if FOG_MAP[type]
      unless(@connections[type])
        if(type == :compute)
          @connections[:compute] = Fog::Compute::AWS.new(@creds)
        else
          Fog.credentials = Fog.symbolize_credentials(@creds)
          @connections[type] = Fog::AWS[type]
          Fog.credentials = {}
        end
      end
      @connections[type]
    end
    alias_method :aws, :build_connection

    DEFAULT_STACK_STATUS = %w(
      CREATE_IN_PROGRESS CREATE_COMPLETE CREATE_FAILED
      ROLLBACK_IN_PROGRESS ROLLBACK_COMPLETE ROLLBACK_FAILED
      UPDATE_IN_PROGRESS UPDATE_COMPLETE UPDATE_COMPLETE_CLEANUP_IN_PROGRESS
      UPDATE_ROLLBACK_IN_PROGRESS UPDATE_ROLLBACK_FAILED
      UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS UPDATE_ROLLBACK_COMPLETE
      DELETE_IN_PROGRESS DELETE_FAILED
    )

    def stacks(args={})
      status = args[:status] || DEFAULT_STACK_STATUS
      key = status.hash
      @memo[:stack_list].delete(key) if args[:force_refresh]
      count = 0
      if(status.map(&:downcase).include?('none'))
        filter = {}
      else
        filter = Hash[*(
            status.map do |n|
              count += 1
              ["StackStatusFilter.member.#{count}", n]
            end.flatten
        )]
      end
      unless(@memo[:stack_list][key])
        @memo[:stack_list][key] = aws(:cloud_formation).list_stacks(filter).body['StackSummaries']
      end
      @memo[:stack_list][key]
    end

    def stack(name)
      unless(@memo[:stacks][name])
        @memo[:stacks][name] = Stack.new(name, self)
      end
      @memo[:stacks][name]
    end

    def create_stack(name, definition)
      Stack.create(name, definition, self)
    end

    # Output Helpers

    def process(things, args={})
      @event_ids ||= []
      processed = things.reverse.map do |thing|
        next if @memo[:event_ids].include?(thing['EventId'])
        @event_ids.push(thing['EventId']).compact!
        if(args[:attributes])
          args[:attributes].map do |key|
            thing[key].to_s
          end
        else
          thing.values
        end
      end
      args[:flat] ? processed.flatten : processed
    end

    def get_titles(thing, args={})
      attrs = args[:attributes] || []
      if(attrs.empty?)
        hash = thing.is_a?(Array) ? thing.first : thing
        hash ||= {}
        attrs = hash.keys
      end
      titles = attrs.map do |key|
        key.gsub(/([a-z])([A-Z])/, '\1 \2')
      end.compact
      if(args[:format])
        titles.map{|s| @ui.color(s, :bold)}
      else
        titles
      end
    end
  end
end
