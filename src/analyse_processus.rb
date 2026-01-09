#!/usr/bin/env ruby
# Analyse de processus - Usage: ruby analyse_processus.rb <PID>

pid = ARGV[0]&.to_i || (puts "Usage: #{$0} <PID>"; exit 1)

exit 1 unless File.exist?("/proc/#{pid}")

# Lecture des infos de base
status = File.read("/proc/#{pid}/status")
stat = File.read("/proc/#{pid}/stat").split
name = File.read("/proc/#{pid}/comm").strip
cmdline = File.read("/proc/#{pid}/cmdline").gsub("\0", " ")

# État du processus
state = status[/State:\s+(\S+)/, 1]
states = {'R'=>'Running', 'S'=>'Sleeping', 'D'=>'Disk Sleep', 'Z'=>'Zombie', 'T'=>'Stopped'}

# CPU et Mémoire
cpu_time = (stat[13].to_i + stat[14].to_i) / 100.0
vm_size = status[/VmSize:\s+(\d+)/, 1].to_i / 1024
vm_rss = status[/VmRSS:\s+(\d+)/, 1].to_i / 1024

# Fichiers ouverts
open_files = Dir.glob("/proc/#{pid}/fd/*").map { |f| File.readlink(f) rescue nil }.compact

# Appels système 
syscalls = []
if Process.uid == 0
  syscalls = `timeout 1 strace -p #{pid} -c 2>&1`.lines
    .select { |l| l.match?(/^\s*\d/) }
    .map { |l| l.split.last }
    .first(10) rescue []
end

# Affichage du rapport
puts "\n═══ RAPPORT PROCESSUS PID #{pid} ═══"
puts "\nNom: #{name}"
puts "Commande: #{cmdline}"
puts "État: #{state} (#{states[state]})"
puts "\nCPU: #{cpu_time.round(2)}s"
puts "Mémoire virtuelle: #{vm_size} MB"
puts "Mémoire résidente: #{vm_rss} MB"
puts "\nFichiers ouverts (#{open_files.size}):"
open_files.first(10).each { |f| puts "  • #{f}" }
puts "  ... (#{open_files.size - 10} autres)" if open_files.size > 10

unless syscalls.empty?
  puts "\nAppels système récents:"
  syscalls.each { |sc| puts "  • #{sc}" }
end

puts "\n" + "═" * 40
