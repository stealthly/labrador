require 'net/ssh'
require 'net/ssh/gateway'

def jumpbox(user_name, cmd, private_ip)
    puts "\tSSH to #{private_ip} as #{user_name} through #{$opts[:nat_node_name]} as ec2-user to run #{cmd}".bold.yellow
    gateway = Net::SSH::Gateway.new($opts[:nat_node_name], 'ec2-user')
    gateway.ssh(private_ip, user_name) do |ssh|
        puts "\t#{ssh.exec!(cmd)}"
    end
end
def ssh_command(host, username, cmd)
    Net::SSH.start(host, username) do |ssh|
        command_output=ssh_exec!(ssh, cmd)
        return command_output
    end     
end
def ssh_exec!(ssh, command)
  # I am not awesome enough to have made this method myself
  # I've just modified it a bit
  # Originally submitted by 'flitzwald' over here: http://stackoverflow.com/a/3386375
  stdout_data = ""
  stderr_data = ""
  exit_code = nil
 
  ssh.open_channel do |channel|
    channel.exec(command) do |ch, success|
      unless success
        abort "FAILED: couldn't execute command (ssh.channel.exec)"
      end
      channel.on_data do |ch,data|
        stdout_data+=data
      end
 
      channel.on_extended_data do |ch,type,data|
        stderr_data+=data
      end
 
      channel.on_request("exit-status") do |ch,data|
        exit_code = data.read_long
      end
    end
  end
  ssh.loop
  [stdout_data, stderr_data, exit_code]
end

def is_dns_setup()
    puts "Checking if dns is setup..."
    Net::SSH.start($opts[:nat_node_name], 'ec2-user') do |ssh|
        command_output=ssh_exec!(ssh, "host #{$opts[:dns_node_name]} #{$opts[:private_ip_address]}")
        #if !command_output[0].empty?
        #    puts "\n\tSTDOUT:".green
        #    puts "\t#{command_output[0]}"
        #end
        #if !command_output[1].empty?
        #    puts "\n\tSTDERR:".red
        #    puts "\t#{command_output[1]}"
        #end
        #puts "\n\tEXIT CODE: ".yellow + "\t#{command_output[2]}"
        return  command_output
    end

end
