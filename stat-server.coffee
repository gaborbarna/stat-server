_ = require 'underscore'
http = require 'http'
fs = require 'fs'
sys = require 'sys'
os = require 'os'
exec = (require 'child_process').exec
udp = require 'dgram'
hostname = (require 'os').hostname()
iface = 'wlan0'
udp_port = 8125
ip_addr = '10.0.0.100'

every = (delay, cb) ->
  setInterval cb, delay*1000

prev_total = prev_idle = 0

every 1, ->
  fs.readFile '/proc/stat', (err, data) ->
    send_udp [parse_stat data.toString()]

every 1, ->
  child = exec 'acpi -t', (err, stdout, sdterr) ->
    send_udp parse_thermal stdout

every 60, ->
  child = exec 'acpi -b', (err, stdout, sdterr) ->
    send_udp [parse_battery stdout]

prev_bytes = {'tx_bytes': null, 'rx_bytes' : null}

every 1, ->
  _.each (_.keys prev_bytes), (f) ->
    fs.readFile "/sys/class/net/#{iface}/statistics/#{f}", (err, data) ->
      send_udp [parse_bytes data, f]

every 10, ->
  send_udp [format_output 'used_mem', os.totalmem() - os.freemem(), 'c']

parse_bytes = (data, f) ->
  bytes = if prev_bytes[f] isnt null then data - prev_bytes[f] else 0
  prev_bytes[f] = data
  format_output f, bytes, 'ms'

send_udp = (datas) ->
  _.each datas, (data) ->
    msg = new Buffer data
    console.log data
    client = udp.createSocket 'udp4'
    client.send msg, 0, msg.length, udp_port, ip_addr, (err, bytes) ->
      client.close()

calc_load = (total, idle) ->
  d_total = total - prev_total
  d_idle = idle - prev_idle
  prev_total = total
  prev_idle = idle
  (d_total - d_idle) / d_total * 100
        
parse_stat = (data) ->
  stats = data.match(/^cpu[^0-9]*([ [0-9]*]*).*/)?[1].trim().split ' '
  idle = stats[3]*1
  total = stats[0..3].reduce (t, s) -> t*1 + s*1
  val = calc_load total, idle
  format_output 'load', val, 'ms'

parse_thermal = (data) ->
  _.map (data.split '\n')[0..-2], (line, i) ->
    val = (line.split ' ')[3]
    format_output "therm#{i}", val, 'ms'

parse_battery = (data) ->
  val = (data.split ' ')[3][0..-3]
  format_output 'battery', val, 'g'
  
format_output = (name, value, type) ->
  "#{hostname}.#{name}:#{value}|#{type}"
