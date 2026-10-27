/// The fixed script run on a remote machine (`ssh host sh -s`, script on standard input). Nothing
/// is installed there and nothing user-supplied is ever interpolated into it. It prints
/// `key=value` lines that `RemoteMetricsParser` reads; byte counters are cumulative so the app can
/// compute rates from two samples.
///
/// Commands that might read standard input are given `</dev/null`, because `sh -s` reads the rest
/// of the script from the same stream.
public enum RemoteScript {
    public static let source = #"""
    LC_ALL=C
    export LC_ALL
    pick() {
      printf '%s\n' "$1" | sort -k1,1nr | head -n 8
      printf '%s\n' "$1" | sort -k2,2nr | head -n 8
    }
    os=$(uname -s </dev/null)
    echo "os=$os"
    if [ "$os" = "Linux" ]; then
      echo "cores=$(getconf _NPROCESSORS_ONLN </dev/null 2>/dev/null)"
      awk 'NR==1 {printf "cpu=%.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f\n", $2, $3, $4, $5, $6, $7, $8, $9}' /proc/stat
      awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {print "mem=" t, a}' /proc/meminfo
      awk '{print "load=" $1, $2, $3}' /proc/loadavg
      awk '{print "uptime=" $1}' /proc/uptime
      awk -F'[: ]+' 'NR>2 && $2!="lo" && $2 !~ /^(docker|veth|br-|virbr|cni|flannel|cali)/ {rx+=$3; tx+=$11} END {printf "net=%.0f %.0f\n", rx, tx}' /proc/net/dev
      awk '$3 ~ /^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$/ {r+=$6; w+=$10} END {printf "disk=%.0f %.0f\n", r*512, w*512}' /proc/diskstats
      if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits </dev/null 2>/dev/null | head -n 1 | awk '{print "gpu=" $1}'
      fi
      groups=$(ps -eo pcpu=,rss=,comm= </dev/null 2>/dev/null | awk '
        { c = $1; m = $2; sub(/^[ ]*[^ ]+[ ]+[^ ]+[ ]+/, ""); cpu[$0] += c; mem[$0] += m }
        END { for (n in cpu) if (cpu[n] > 0 || mem[n] > 0) printf "%.1f %.0f %s\n", cpu[n], mem[n], n }')
      pick "$groups" | awk 'NF && !seen[$0]++' | sed 's/^/proc=/'
      t=""
      for h in /sys/class/hwmon/hwmon*; do
        case "$(cat "$h/name" 2>/dev/null)" in
          coretemp|k10temp|zenpower|cpu_thermal|cpu-thermal|soc_thermal)
            t=$(cat "$h"/temp*_input 2>/dev/null | sort -n | tail -n 1); break ;;
        esac
      done
      if [ -z "$t" ]; then
        for z in /sys/class/thermal/thermal_zone*; do
          case "$(cat "$z/type" 2>/dev/null)" in
            x86_pkg_temp|cpu*|soc*|*cpu-thermal*) t=$(cat "$z/temp" 2>/dev/null); break ;;
          esac
        done
      fi
      if [ -n "$t" ]; then echo "temp=$t"; fi
    elif [ "$os" = "Darwin" ]; then
      echo "cores=$(sysctl -n hw.logicalcpu </dev/null)"
      t=$(top -l 2 -s 1 -n 4000 -stats pid,cpu,mem </dev/null 2>/dev/null)
      printf '%s\n' "$t" | grep '^CPU usage' | tail -n 1 | sed 's/^/cpuline=/'
      echo "memtotal=$(sysctl -n hw.memsize </dev/null)"
      vm_stat </dev/null | sed 's/^/vm=/'
      echo "load=$(sysctl -n vm.loadavg </dev/null | tr -d '{}')"
      echo "boottime=$(sysctl -n kern.boottime </dev/null | sed 's/^{ sec = \([0-9]*\),.*/\1/')"
      echo "now=$(date +%s)"
      netstat -ibn </dev/null | awk '$1 ~ /^en[0-9]+$/ && $3 ~ /^<Link/ {rx+=$(NF-4); tx+=$(NF-1)} END {printf "net=%.0f %.0f\n", rx, tx}'
      groups=$({ ps -Ao pid=,comm= </dev/null 2>/dev/null; echo '--'; printf '%s\n' "$t" | awk '/^PID/ {n++; next} n == 2'; } | awk '
        $0 == "--" { s = 1; next }
        s == 0 { p = $1; sub(/^[ ]*[0-9]+[ ]+/, ""); n = $0
          if (match(n, /[^\/]*\.app\//)) n = substr(n, RSTART, RLENGTH - 5); else sub(/.*\//, "", n)
          app[p] = n; next }
        NF >= 3 && ($1 in app) { m = $3; sub(/[+-]$/, "", m); u = substr(m, length(m)); v = substr(m, 1, length(m) - 1) + 0
          k = (u == "K") ? v : ((u == "M") ? v * 1024 : ((u == "G") ? v * 1048576 : ((u == "T") ? v * 1073741824 : v / 1024)))
          cpu[app[$1]] += $2; mem[app[$1]] += k }
        END { for (n in cpu) if (cpu[n] > 0 || mem[n] > 0) printf "%.1f %.0f %s\n", cpu[n], mem[n], n }')
      pick "$groups" | awk 'NF && !seen[$0]++' | sed 's/^/proc=/'
    fi
    """#
}
