# parse_paths.tcl
# Reads paths.txt with columns: Startpoint, Endpoint, Slack
# Prints:
#  - total number of paths
#  - number of paths with negative slack
#  - list of paths in top 5% worst (lowest slack)

set infile "./$stage/paths.txt"
set top_pct 0.05

# ---- Read file ----
set fp [open $infile r]
set lines [split [read $fp] "\n"]
close $fp

# Each path record: {start end slack line}
set paths {}
set neg_count 0

foreach line $lines {
    set line [string trim $line]
    if {$line eq ""} { continue }
    # Skip header/separator
    if {[string match "Startpoint*" $line]} { continue }
    if {[regexp {^-+$} $line]} { continue }

    # Slack is the last token (float, can be negative)
    # Startpoint + Endpoint can include spaces, so parse by capturing last number
    if {![regexp {^(.*\S)\s+(-?[0-9]+(?:\.[0-9]+)?)$} $line -> se slack_str]} {
        continue
    }
    set slack [expr {double($slack_str)}]

    # Split remaining "start endpoint" part by 2+ spaces (column separation)
    # This matches your fixed-width table formatting.
    set parts [regexp -all -inline {\S.*?(?=\s{2,}|$)} $se]
    if {[llength $parts] < 2} {
        # fallback: try greedy split by multiple spaces
        set parts [split $se "\t"]
    }
    set start [string trim [lindex $parts 0]]
    set end   [string trim [lindex $parts 1]]

    lappend paths [list $start $end $slack $line]
    if {$slack < 0.0} { incr neg_count }
}

set total [llength $paths]
puts "Total paths: $total"
puts "Negative slack paths: $neg_count"

if {$total == 0} {
    puts "No paths parsed. Check input format: $infile"
    return
}

# ---- Sort by slack ascending (worst first) ----
set paths_sorted [lsort -real -increasing -index 2 $paths]

# ---- Top 5% worst ----
set top_n [expr {int(ceil($total * $top_pct))}]
if {$top_n < 1} { set top_n 1 }

puts "Top [expr {$top_pct*100.0}]% worst paths (count=$top_n):"
set top_paths [lrange $paths_sorted 0 [expr {$top_n - 1}]]

# Print in same compact format + also save to file
set out_top "./$stage/top5pct_worst_paths.txt"
set fo [open $out_top w]
puts $fo "Total paths: $total"
puts $fo "Negative slack paths: $neg_count"
puts $fo "Top [expr {$top_pct*100.0}]% worst paths (count=$top_n):"
puts $fo "Startpoint\tEndpoint\tSlack"
foreach rec $top_paths {
    set start [lindex $rec 0]
    set end   [lindex $rec 1]
    set slack [lindex $rec 2]
    puts [format "%.4f  %s  ->  %s" $slack $start $end]
    puts $fo "$start\t$end\t$slack"
}
close $fo
puts "Wrote: $out_top"