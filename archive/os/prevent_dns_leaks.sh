#! /bin/bash
#
# By default, Ubuntu will use your ISPs DNS, as opposed to the VPN
# provider's. At least on 16.04, this can be resolved by installing the three
# packages below. Note, this requires hitting enter in an ncurses program, so
# it's slightly tricky to automate.
#
# Instructions tested and seem to work! As per
# https://anonymous-vpn.biz/blog/dns-leak-after-ubuntu-update/

sudo apt-get install openresolv nscd unbound
