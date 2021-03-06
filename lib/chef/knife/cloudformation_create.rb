require 'sparkle_formation'
require 'pathname'
require 'knife-cloudformation/cloudformation_base'

class Chef
  class Knife
    class CloudformationCreate < Knife

      include KnifeCloudformation::KnifeBase

      banner 'knife cloudformation create NAME'

      module Options
        class << self
          def included(klass)
            klass.class_eval do

              attr_accessor :action_type

              option(:parameter,
                :short => '-p KEY:VALUE',
                :long => '--parameter KEY:VALUE',
                :description => 'Set parameter. Can be used multiple times.',
                :proc => lambda {|val|
                  parts = val.split(':')
                  key = parts.first
                  value = parts[1, parts.size].join(':')
                  Chef::Config[:knife][:cloudformation][:options][:parameters] ||= Mash.new
                  Chef::Config[:knife][:cloudformation][:options][:parameters][key] = value
                }
              )
              option(:timeout,
                :short => '-t MIN',
                :long => '--timeout MIN',
                :description => 'Set timeout for stack creation',
                :proc => lambda {|val|
                  Chef::Config[:knife][:cloudformation][:options][:timeout_in_minutes] = val
                }
              )
              option(:rollback,
                :short => '-R',
                :long => '--[no]-rollback',
                :description => 'Rollback on stack creation failure',
                :boolean => true,
                :default => true,
                :proc => lambda {|val| Chef::Config[:knife][:cloudformation][:options][:disable_rollback] = !val }
              )
              option(:capability,
                :short => '-C CAPABILITY',
                :long => '--capability CAPABILITY',
                :description => 'Specify allowed capabilities. Can be used multiple times.',
                :proc => lambda {|val|
                  Chef::Config[:knife][:cloudformation][:options][:capabilities] ||= []
                  Chef::Config[:knife][:cloudformation][:options][:capabilities].push(val).uniq!
                }
              )
              option(:processing,
                :long => '--[no-]processing',
                :description => 'Call the unicorns and explode the glitter bombs',
                :boolean => true,
                :default => false,
                :proc => lambda {|val| Chef::Config[:knife][:cloudformation][:processing] = val }
              )
              option(:polling,
                :long => '--[no-]poll',
                :description => 'Enable stack event polling.',
                :boolean => true,
                :default => true,
                :proc => lambda {|val| Chef::Config[:knife][:cloudformation][:poll] = val }
              )
              option(:notifications,
                :long => '--notification ARN',
                :description => 'Add notification ARN. Can be used multiple times.',
                :proc => lambda {|val|
                  Chef::Config[:knife][:cloudformation][:options][:notification_ARNs] ||= []
                  Chef::Config[:knife][:cloudformation][:options][:notification_ARNs].push(val).uniq!
                }
              )
              option(:file,
                :short => '-f PATH',
                :long => '--file PATH',
                :description => 'Path to Cloud Formation to process',
                :proc => lambda {|val|
                  Chef::Config[:knife][:cloudformation][:file] = val
                }
              )
              option(:interactive_parameters,
                :long => '--[no-]parameter-prompts',
                :boolean => true,
                :default => true,
                :description => 'Do not prompt for input on dynamic parameters',
                :default => true
              )
              option(:print_only,
                :long => '--print-only',
                :description => 'Print template and exit'
              )
              option(:base_directory,
                :long => '--cloudformation-directory PATH',
                :description => 'Path to cloudformation directory',
                :proc => lambda {|val| Chef::Config[:knife][:cloudformation][:base_directory] = val}
              )
              option(:no_base_directory,
                :long => '--no-cloudformation-directory',
                :description => 'Unset any value used for cloudformation path',
                :proc => lambda {|*val| Chef::Config[:knife][:cloudformation][:base_directory] = nil}
              )

              %w(rollback polling interactive_parameters).each do |key|
                if(Chef::Config[:knife][:cloudformation][key].nil?)
                  Chef::Config[:knife][:cloudformation][key] = true
                end
              end
            end
          end
        end
      end

      include Options

      def run
        create_or_update_run(:create)
      end

    end
  end
end
