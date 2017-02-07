#
# AIX PowerHA7 plugin
# Author:: Michal Swierczewski <michal.swierczewski@pl.ibm.com>
#
# cltopinfo
# lscluster -i
# clRGinfo
# cldump
# cllsif -p
# clmgr
# lssrc -ls clstrmgrES
# /opt/chefdk_master/embedded/bin/irb
# /opt/chef/embedded/lib/ruby/gems/2.1.0/gems/ohai-8.17.1/lib/ohai/plugins/aix

# rubocop:disable LineLength
# rubocop:disable MethodCallParentheses
# rubocop:disable Next
# rubocop:disable EmptyLiteral

Ohai.plugin(:Powerha7) do
  provides 'cluster'

  collect_data(:aix) do
    cluster Mash.new

    ## SHELL
    # cluster info
    out_cl = shell_out('clmgr q cl')
    cl_lst = out_cl.stdout.split("\n")

    # topology -> cllsif
    so = shell_out('cllsif')
    output = so.stdout.split("\n")

    # nodes name -> clmgr query no
    out_no = shell_out('clmgr query no')
    nodes = out_no.stdout.split("\n")

    # resource group -> clmgr query rg
    out_rg = shell_out('clmgr query rg')
    rg_lst = out_rg.stdout.split("\n")

    # repo disks -> output from # cluster info
    # out_rd = shell_out("clmgr query rp")
    # rd_lst = out_rd.stdout.split("\n")
    out_rd = /(?<=\").+?(?=\")/.match(cl_lst[5]).to_s
    rd_lst = out_rd.split(', ')
    # change in fly:
    rd_lst.map! { |rd| /[^ ]*/.match(rd) }

    # vg -> clmgr query vg
    out_vg = shell_out('clmgr query vg')
    vg_lst = out_vg.stdout.split("\n")

    # start/stop script
    # application controller -> clmgr q ac <ac>
    out_ac = shell_out('clmgr query ac')
    ac_lst = out_ac.stdout.split("\n")

    cluster[:cluster_name] = /(?<=\").+?(?=\")/.match(cl_lst[0])
    cluster[:cluster_version] = /(?<=\").+?(?=\")/.match(cl_lst[6])

    ## TOPOLOGY
    cluster[:topology] = {}
    nodes.each do |nn|
      cluster[:topology][nn] = []
    end

    cluster[:topology].keys().each do |k|
      # 2, first two are header and empty line
      (2..output.length - 1).each do |i|
        if output[i].split(' ')[5] == k
          cluster[:topology][k] = Array.new unless cluster[:topology][k]
          cluster[:topology][k] << {
            hostname: output[i].split(' ')[0],
            type: output[i].split(' ')[1],
            network: output[i].split(' ')[2],
            address: output[i].split(' ')[6]
          }
        end
      end
    end

    ## RESOURCE
    cluster[:resource] = {
      volume_group: vg_lst,
      repo_disk: rd_lst,
      application_controller: {}
    }

    ac_lst.each do |ac|
      cluster[:resource][:application_controller][ac] = []
      cluster[:resource][:application_controller][ac] = Array.new unless cluster[:resource][:application_controller][ac]
      out = shell_out("clmgr q ac #{ac}")
      out_lst = out.stdout.split("\n")
      cluster[:resource][:application_controller][ac] << {
        startscript: /(?<=\").+?(?=\")/.match(out_lst[2]),
        stopscript: /(?<=\").+?(?=\")/.match(out_lst[3])
      }
    end

    ## STATUS
    cluster[:status] = {
      cluster_name: /(?<=\").+?(?=\")/.match(cl_lst[0]),
      cluster_state: /(?<=\").+?(?=\")/.match(cl_lst[2]),
      resource_group: {}
    }

    rg_lst.each do |rg|
      cluster[:status][:resource_group][rg] = []
      cluster[:status][:resource_group][rg] = Array.new unless cluster[:status][:resource_group][rg]
      out = shell_out("clmgr -q rg #{rg}")
      out_lst = out.stdout.split("\n")
      cluster[:status][:resource_group][rg] << {
        current_node: /(?<=\").+?(?=\")/.match(out_lst[1]),
        state: /(?<=\").+?(?=\")/.match(out_lst[3]),
        applications: /(?<=\").+?(?=\")/.match(out_lst[5]),
        volume_group: /(?<=\").+?(?=\")/.match(out_lst[13])
      }
    end
  end
end
