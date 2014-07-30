require 'chef/knife'
require 'knife-cloudformation/utils'
require 'knife-cloudformation/aws_commons'

module KnifeCloudformation

  module KnifeBase

    module InstanceMethods

      def aws
        self.class.con(ui)
      end

      def _debug(e, *args)
        if(ENV['DEBUG'])
          ui.fatal "Exception information: #{e.class}: #{e}\n#{e.backtrace.join("\n")}\n"
          args.each do |string|
            ui.fatal string
          end
        end
      end

      def stack(name)
        self.class.con(ui).stack(name, :ignore_seeds)
      end

      def allowed_attributes
        Chef::Config[:knife][:cloudformation][:attributes] || default_attributes
      end

      def default_attributes
        %w(Timestamp StackName StackId)
      end

      def attribute_allowed?(attr)
        config[:all_attributes] || allowed_attributes.include?(attr)
      end

      def poll_stack(name)
        knife_events = Chef::Knife::CloudformationEvents.new
        knife_events.name_args.push(name)
        Chef::Config[:knife][:cloudformation][:poll] = true
        knife_events.run
      end

      def things_output(stack, things, what, *args)
        unless(args.include?(:no_title))
          output = aws.get_titles(things, :format => true, :attributes => allowed_attributes)
        else
          output = []
        end
        columns = allowed_attributes.size
        output += aws.process(things, :flat => true, :attributes => allowed_attributes)
        output.compact.flatten
        if(output.empty?)
          ui.warn 'No information found' unless args.include?(:ignore_empty_output)
        else
          ui.info "#{what.to_s.capitalize} for stack: #{ui.color(stack, :bold)}" if stack
          ui.info "#{ui.list(output, :uneven_columns_across, columns)}"
        end
      end

      def get_things(stack=nil, message=nil)
        begin
          yield
        rescue => e
          ui.fatal "#{message || 'Failed to retrieve information'}#{" for requested stack: #{stack}" if stack}"
          ui.fatal "Reason: #{e}"
          _debug(e)
          exit 1
        end
      end

      def populate_parameters!(stack)
        if(Chef::Config[:knife][:cloudformation][:interactive_parameters])
          if(stack['Parameters'])
            Chef::Config[:knife][:cloudformation][:options][:parameters] ||= Mash.new
            stack['Parameters'].each do |k,v|
              next if Chef::Config[:knife][:cloudformation][:options][:parameters][k]
              valid = false
              until(valid)
                default = Chef::Config[:knife][:cloudformation][:options][:parameters][k] || v['Default']
                answer = ui.ask_question("#{k.split(/([A-Z]+[^A-Z]*)/).find_all{|s|!s.empty?}.join(' ')}: ", :default => default)
                validation = KnifeCloudformation::AwsCommons::Stack::ParameterValidator.validate(answer, v)
                if(validation == true)
                  Chef::Config[:knife][:cloudformation][:options][:parameters][k] = answer
                  valid = true
                else
                  validation.each do |validation_error|
                    ui.error validation_error.last
                  end
                end
              end
            end
          end
        end
      end

      def set_paths_and_discover_file!
        if(Chef::Config[:knife][:cloudformation][:base_directory])
          SparkleFormation.components_path = File.join(
            Chef::Config[:knife][:cloudformation][:base_directory], 'components'
          )
          SparkleFormation.dynamics_path = File.join(
            Chef::Config[:knife][:cloudformation][:base_directory], 'dynamics'
          )
        end
        unless(Chef::Config[:knife][:cloudformation][:file])
          Chef::Config[:knife][:cloudformation][:file] = prompt_for_file(
            Chef::Config[:knife][:cloudformation][:base_directory] || File.join(Dir.pwd, 'cloudformation')
          )
        else
          unless(Pathname(Chef::Config[:knife][:cloudformation][:file]).absolute?)
            Chef::Config[:knife][:cloudformation][:file] = File.join(
              Chef::Config[:knife][:cloudformation][:base_directory] || File.join(Dir.pwd, 'cloudformation'),
              Chef::Config[:knife][:cloudformation][:file]
            )
          end
        end
      end

      def prompt_for_file(dir)
        directory = Dir.new(dir)
        directories = directory.map do |d|
          if(!d.start_with?('.') && !%w(dynamics components).include?(d) && File.directory?(path = File.join(dir, d)))
            path
          end
        end.compact.sort
        files = directory.map do |f|
          if(!f.start_with?('.') && File.file?(path = File.join(dir, f)))
            path
          end
        end.compact.sort
        if(directories.empty? && files.empty?)
          ui.fatal 'No formation paths discoverable!'
        else
          output = ['Please select the formation to create']
          output << '(or directory to list):' unless directories.empty?
          ui.info output.join(' ')
          output.clear
          idx = 1
          valid = {}
          unless(directories.empty?)
            output << ui.color('Directories:', :bold)
            directories.each do |path|
              valid[idx] = {:path => path, :type => :directory}
              output << [idx, "#{File.basename(path).sub('.rb', '').split(/[-_]/).map(&:capitalize).join(' ')}"]
              idx += 1
            end
          end
          unless(files.empty?)
            output << ui.color('Templates:', :bold)
            files.each do |path|
              valid[idx] = {:path => path, :type => :file}
              output << [idx, "#{File.basename(path).sub('.rb', '').split(/[-_]/).map(&:capitalize).join(' ')}"]
              idx += 1
            end
          end
          max = idx.to_s.length
          output.map! do |o|
            if(o.is_a?(Array))
              "  #{o.first}.#{' ' * (max - o.first.to_s.length)} #{o.last}"
            else
              o
            end
          end
          ui.info "#{output.join("\n")}\n"
          response = ask_question('Enter selection: ').to_i
          unless(valid[response])
            ui.fatal 'How about using a real value'
            exit 1
          else
            entry = valid[response.to_i]
            if(entry[:type] == :directory)
              prompt_for_file(entry[:path])
            else
              Chef::Config[:knife][:cloudformation][:file] = entry[:path]
            end
          end
        end
      end

      def polling(name)
        poll_stack(name)
        if(stack(name).success?)
          ui.info "Stack #{action_type} complete: #{ui.color('SUCCESS', :green)}"
          knife_output = Chef::Knife::CloudformationDescribe.new
          knife_output.name_args.push(name)
          knife_output.config[:outputs] = true
          knife_output.run
        else
          ui.fatal "#{action_type} of new stack #{ui.color(name, :bold)}: #{ui.color('FAILED', :red, :bold)}"
          ui.info ""
          knife_inspect = Chef::Knife::CloudformationInspect.new
          knife_inspect.name_args.push(name)
          knife_inspect.config[:instance_failure] = true
          knife_inspect.run
          exit 1
        end
      end

      def create_or_update_run(create_or_update)
        @action_type = self.class.name.split('::').last.sub('Cloudformation', '').upcase
        name = name_args.first
        unless(name)
          ui.fatal "Formation name must be specified!"
          exit 1
        end

        unless(Chef::Config[:knife][:cloudformation][:template])
          set_paths_and_discover_file!
          unless(File.exists?(Chef::Config[:knife][:cloudformation][:file].to_s))
            ui.fatal "Invalid formation file path provided: #{Chef::Config[:knife][:cloudformation][:file]}"
            exit 1
          end
        end

        if(Chef::Config[:knife][:cloudformation][:template])
          file = Chef::Config[:knife][:cloudformation][:template]
        elsif(Chef::Config[:knife][:cloudformation][:processing])
          file = SparkleFormation.compile(Chef::Config[:knife][:cloudformation][:file])
        else
          file = _from_json(File.read(Chef::Config[:knife][:cloudformation][:file]))
        end
        if(config[:print_only])
          ui.warn 'Print only requested'
          ui.info _format_json(file)
          exit 1
        end
        ui.info "#{ui.color('Cloud Formation: ', :bold)} #{ui.color(action_type, :green)}"
        stack_info = "#{ui.color('Name:', :bold)} #{name}"
        if(Chef::Config[:knife][:cloudformation][:path])
          stack_info << " #{ui.color('Path:', :bold)} #{Chef::Config[:knife][:cloudformation][:file]}"
          if(Chef::Config[:knife][:cloudformation][:disable_processing])
            stack_info << " #{ui.color('(not pre-processed)', :yellow)}"
          end
        end
        ui.info "  -> #{stack_info}"
        populate_parameters!(file)
        stack_def = KnifeCloudformation::AwsCommons::Stack.build_stack_definition(file, Chef::Config[:knife][:cloudformation][:options])
        begin
          aws.send("#{create_or_update}_stack", name, stack_def)
        rescue => e
          ui.fatal "Failed to #{create_or_update} stack #{name}. Reason: #{e}"
          _debug(e, "Generated template used:\n#{_format_json(stack['TemplateBody'])}")
          exit 1
        end
        if(Chef::Config[:knife][:cloudformation][:polling])
          polling(name)
        else
          ui.warn 'Stack state polling has been disabled.'
          ui.info "Stack creation initialized for #{ui.color(name, :green)}"
        end
      end
    end

    module ClassMethods

      def con(ui=nil)
        unless(@common)
          @common = KnifeCloudformation::AwsCommons.new(
            :ui => ui,
            :fog => {
              :aws_access_key_id => _key,
              :aws_secret_access_key => _secret,
              :region => _region
            }
          )
        end
        @common
      end

      def _key
        Chef::Config[:knife][:cloudformation][:credentials][:key] ||
          Chef::Config[:knife][:aws_access_key_id]
      end

      def _secret
        Chef::Config[:knife][:cloudformation][:credentials][:secret] ||
          Chef::Config[:knife][:aws_secret_access_key]
      end

      def _region
        Chef::Config[:knife][:cloudformation][:credentials][:region] ||
          Chef::Config[:knife][:region]
      end

    end

    class << self
      def included(klass)
        klass.instance_eval do

          extend KnifeCloudformation::KnifeBase::ClassMethods
          include KnifeCloudformation::KnifeBase::InstanceMethods
          include KnifeCloudformation::Utils::JSON
          include KnifeCloudformation::Utils::AnimalStrings

          deps do
            require 'fog'
            Chef::Config[:knife][:cloudformation] ||= Mash.new
            Chef::Config[:knife][:cloudformation][:credentials] ||= Mash.new
            Chef::Config[:knife][:cloudformation][:options] ||= Mash.new
          end

          option(:key,
            :short => '-K KEY',
            :long => '--key KEY',
            :description => 'AWS access key id',
            :proc => lambda {|val|
              Chef::Config[:knife][:cloudformation][:credentials][:key] = val
            }
          )
          option(:secret,
            :short => '-S SECRET',
            :long => '--secret SECRET',
            :description => 'AWS secret access key',
            :proc => lambda {|val|
              Chef::Config[:knife][:cloudformation][:credentials][:secret] = val
            }
          )
          option(:region,
            :short => '-r REGION',
            :long => '--region REGION',
            :description => 'AWS region',
            :proc => lambda {|val|
              Chef::Config[:knife][:cloudformation][:credentials][:region] = val
            }
          )


          # Populate up the hashes so they are available for knife config
          # with issues of nils
          ['knife.cloudformation.credentials', 'knife.cloudformation.options'].each do |stack|
            stack.split('.').inject(Chef::Config) do |memo, item|
              memo[item.to_sym] = Mash.new unless memo[item.to_sym]
              memo[item.to_sym]
            end
          end

          Chef::Config[:knife][:cloudformation] ||= Mash.new

        end
      end
    end
  end

end
