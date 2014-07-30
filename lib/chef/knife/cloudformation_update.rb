require 'knife-cloudformation/cloudformation_base'
require File.join(File.dirname(__FILE__), 'cloudformation_create')

class Chef
  class Knife
    class CloudformationUpdate < Knife
      banner 'knife cloudformation update NAME'

      include KnifeCloudformation::KnifeBase
      include CloudformationCreate::Options

      def run
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
        create_stack(name, stack_def)
      end

      def create_stack(name, stack)
        begin
          res = aws_con.update_stack(name, stack)
        rescue => e
          ui.fatal "Failed to update stack #{name}. Reason: #{e}"
          _debug(e, "Generated template used:\n#{_format_json(stack['TemplateBody'])}")
          exit 1
        end
      end

      def action_in_progress?(name)
        stack_status(name) == 'UPDATE_IN_PROGRESS'
      end

      def action_successful?(name)
        stack_status(name) == 'UPDATE_COMPLETE'
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

      private

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

    end
  end
end
