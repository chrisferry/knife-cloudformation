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

    end
  end
end
