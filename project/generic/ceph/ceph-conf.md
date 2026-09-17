# begin crush map
tunable choose_local_tries 0
tunable choose_local_fallback_tries 0
tunable choose_total_tries 50
tunable chooseleaf_descend_once 1
tunable chooseleaf_vary_r 1
tunable chooseleaf_stable 1
tunable straw_calc_version 1
tunable allowed_bucket_algs 54

# devices
device 0 osd.0 class ssd
device 1 osd.1 class ssd
device 2 osd.2 class ssd
device 3 osd.3 class ssd
device 4 osd.4 class ssd
device 5 osd.5 class ssd
device 6 osd.6 class ssd
device 7 osd.7 class ssd
device 8 osd.8 class ssd
device 9 osd.9 class ssd
device 10 osd.10 class ssd
device 11 osd.11 class ssd
device 12 osd.12 class ssd
device 13 osd.13 class ssd
device 14 osd.14 class ssd
device 15 osd.15 class ssd
device 16 osd.16 class ssd
device 17 osd.17 class ssd
device 18 osd.18 class ssd
device 19 osd.19 class ssd
device 20 osd.20 class ssd
device 21 osd.21 class ssd
device 22 osd.22 class ssd
device 23 osd.23 class ssd
device 24 osd.24 class ssd
device 25 osd.25 class ssd
device 26 osd.26 class ssd
device 27 osd.27 class ssd
device 28 osd.28 class ssd
device 29 osd.29 class ssd
device 30 osd.30 class ssd
device 31 osd.31 class ssd
device 32 osd.32 class ssd
device 33 osd.33 class ssd
device 34 osd.34 class ssd
device 35 osd.35 class ssd
device 36 osd.36 class ssd
device 37 osd.37 class ssd
device 38 osd.38 class ssd
device 39 osd.39 class ssd
device 40 osd.40 class ssd
device 41 osd.41 class ssd
device 42 osd.42 class ssd
device 43 osd.43 class ssd
device 44 osd.44 class ssd
device 45 osd.45 class ssd
device 46 osd.46 class ssd
device 47 osd.47 class ssd
device 48 osd.48 class ssd
device 49 osd.49 class ssd
device 50 osd.50 class ssd
device 51 osd.51 class ssd
device 52 osd.52 class ssd
device 53 osd.53 class ssd

# types
type 0 osd
type 1 host
type 2 chassis
type 3 rack
type 4 row
type 5 pdu
type 6 pod
type 7 room
type 8 datacenter
type 9 zone
type 10 region
type 11 root

# buckets
host occ1 {
 id -3  # do not change unnecessarily
 id -4 class ssd  # do not change unnecessarily
 # weight 31.43779
 alg straw2
 hash 0 # rjenkins1
 item osd.0 weight 3.49309
 item osd.1 weight 3.49309
 item osd.2 weight 3.49309
 item osd.3 weight 3.49309
 item osd.4 weight 3.49309
 item osd.5 weight 3.49309
 item osd.6 weight 3.49309
 item osd.7 weight 3.49309
 item osd.8 weight 3.49309
}
host occ2 {
 id -5  # do not change unnecessarily
 id -6 class ssd  # do not change unnecessarily
 # weight 31.43779
 alg straw2
 hash 0 # rjenkins1
 item osd.9 weight 3.49309
 item osd.10 weight 3.49309
 item osd.11 weight 3.49309
 item osd.12 weight 3.49309
 item osd.13 weight 3.49309
 item osd.14 weight 3.49309
 item osd.15 weight 3.49309
 item osd.16 weight 3.49309
 item osd.17 weight 3.49309
}
host occ3 {
 id -7  # do not change unnecessarily
 id -8 class ssd  # do not change unnecessarily
 # weight 31.43779
 alg straw2
 hash 0 # rjenkins1
 item osd.18 weight 3.49309
 item osd.19 weight 3.49309
 item osd.20 weight 3.49309
 item osd.21 weight 3.49309
 item osd.22 weight 3.49309
 item osd.23 weight 3.49309
 item osd.24 weight 3.49309
 item osd.25 weight 3.49309
 item osd.26 weight 3.49309
}
datacenter occ {
 id -15  # do not change unnecessarily
 id -17 class ssd  # do not change unnecessarily
 # weight 94.31337
 alg straw2
 hash 0 # rjenkins1
 item occ1 weight 31.43779
 item occ2 weight 31.43779
 item occ3 weight 31.43779
}
host bocc1 {
 id -9  # do not change unnecessarily
 id -10 class ssd  # do not change unnecessarily
 # weight 31.43779
 alg straw2
 hash 0 # rjenkins1
 item osd.27 weight 3.49309
 item osd.31 weight 3.49309
 item osd.32 weight 3.49309
 item osd.33 weight 3.49309
 item osd.29 weight 3.49309
 item osd.30 weight 3.49309
 item osd.28 weight 3.49309
 item osd.34 weight 3.49309
 item osd.35 weight 3.49309
}
host bocc2 {
 id -11  # do not change unnecessarily
 id -12 class ssd  # do not change unnecessarily
 # weight 31.43779
 alg straw2
 hash 0 # rjenkins1
 item osd.36 weight 3.49309
 item osd.37 weight 3.49309
 item osd.38 weight 3.49309
 item osd.39 weight 3.49309
 item osd.40 weight 3.49309
 item osd.41 weight 3.49309
 item osd.42 weight 3.49309
 item osd.43 weight 3.49309
 item osd.44 weight 3.49309
}
host bocc3 {
 id -13  # do not change unnecessarily
 id -14 class ssd  # do not change unnecessarily
 # weight 31.43779
 alg straw2
 hash 0 # rjenkins1
 item osd.45 weight 3.49309
 item osd.46 weight 3.49309
 item osd.47 weight 3.49309
 item osd.48 weight 3.49309
 item osd.49 weight 3.49309
 item osd.50 weight 3.49309
 item osd.51 weight 3.49309
 item osd.52 weight 3.49309
 item osd.53 weight 3.49309
}
datacenter bocc {
 id -16  # do not change unnecessarily
 id -18 class ssd  # do not change unnecessarily
 # weight 94.31337
 alg straw2
 hash 0 # rjenkins1
 item bocc1 weight 31.43779
 item bocc2 weight 31.43779
 item bocc3 weight 31.43779
}
root r160a {
 id -1  # do not change unnecessarily
 id -2 class ssd  # do not change unnecessarily
 # weight 188.62674
 alg straw2
 hash 0 # rjenkins1
 item occ weight 94.31337
 item bocc weight 94.31337
}

# rules
rule stretch_rule {
 id 0
 type replicated
 step take r160a
 step choose firstn 0 type datacenter
 step chooseleaf firstn 2 type host
 step emit
}

# end crush map