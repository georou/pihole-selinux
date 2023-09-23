# SELinux Policy for Pi-hole

THIS POLICY IS STILL UNDER CONSTANT TESTING.

This policy allows SELinux to continue running in enforcing mode and contains the Pi-hole web service(lighttpd) and FTL binary.

To achieve this, some considerations need to be made:

- The php-cgi engine needs to be labeled differently to contain it separately. This allows other services to use php-cgi for lighttpd and not be confined into the pihole policy. The bin directive location in lighttpd.conf needs to change to a wrapper script with the correct label.

NOTE: This policy is provided as is. I make no claims to be an authority on SELinux. I mainly created this a a learning project for myself. If there's a mistake, let me know so we can learn together.

## Overview of Transitions
```
systemd starts lighttpd
    |
(lighttpd process starts labeled as httpd_t)
    |    
(lighttpd executes fastcgi engine php-cgi-pihole location(wrapper script) in /etc/lighttpd/conf.d/pihole-admin.conf)
    |
(php-cgi-pihole is labeled as pihole_cgi_script_exec_t and thus httpd_t transitions. Transition created by using apache_content_template())
    |
(lighttpd serves content for pi-hole through the pihole_cgi_script_t domain)    


systemd starts pihole-FTL binary
    |
(pihole-FTL binary labeled pihole_exec_t and transitions to the pihole_t domain)
```

## Domains Explained
pihole_t - is the primary domain for the FTL binary. The pihole port is also defined in here; pihole_port_t. The FTL binary currently has DNSmasq builtin.

pihole_cgi_script_t - is the domain concerned with the web serving and php side. Other html and php content in /var/www/html/admin are done through this domain as long as they are labeled correctly.

Any scripts that are executed in /opt/pihole transition to pihole_t. 

## Lighttpd Change Explained
The [pihole-admin.conf](https://github.com/pi-hole/pi-hole/blob/master/advanced/pihole-admin.conf) file shipped with Pi-hole has `"bin-path" => "/usr/bin/php-cgi"` for the fastcgi location. If this is used, when the lighttpd server is started and starts the php-cgi engine, it is normally in the httpd_t domain and thus any of the functions used by the Pi-hole web scripts will be executed under httpd_t. This is not ideal as the httpd_t domain will need to be allowed access to wide range of permissions. Ideally having the php-cgi gateway confined separately is more secure. The easiest way is to have a wrapper script and replacing the bin-path with `"bin-path" => "/usr/local/bin/php-cgi-pihole"`. This allows the transition to function without affecting existing services.

## Testing and To-Do List:
- Find out why Lighttpd(httpd_t) throws a deny execmem when starting lighttpd.service. Related to using pcre2. Lighttpd error log: `pcre2_jit_compile: no more memory, regex`
- Enabling TLS on the Pi-hole WebUI. Lighttpd handles a majority of it, so it might 'just work'
- Fine tune /var/www/html/admin file contexts(.fc)
- Rebuild with disabling dontaudit and comb over logs again
- How updates from upstream are handled. Also look into /etc/.pihole
- systemd service file hardening(sandboxing)(already started)
- Another round of auditing current rules. ie: removing them one by one and testing if they're still needed. A fair amount of code has changed since 2017
- I've seen mentions that Pi-hole V6 will remove using Lighttpd and use civetweb, an embedded web server. Will require a complete rewrite but fundamentally the same, rolled into only one domain; pihole_t

## Notes and Observations
The default lighttpd.conf has server.max-fds set to over 1024. As indicated by comments in the conf file, it triggers an SELinux warning but can be ignored.

The need for dac_override is because of using sudo to execute pihole commands. For example, making changes via the WebUI writes to the /etc/pihole/setupvars.conf file with root. Since DAC permissions are 770 pihole:pihole on /etc/pihole, this triggers SELinux. This should be looked at by the Pi-hole devs to maybe change what user lighttpd/php-cgi runs as? The upcoming V6 of Pi-hole might run the embedded web server as the correct user?

## Installation Guide
Have Pi-hole downloaded and installed following their guide on the website. Currently this policy is applied after Pi-hole is installed - subject to change.
## Pre-Installation
```sh
git clone https://github.com/georou/pihole-selinux.git && cd pihole-selinux
systemctl stop lighttpd.service pihole-FTL.service
sed -i 's+"bin-path" => "/usr/bin/php-cgi"+"bin-path" => "/usr/local/bin/php-cgi-pihole"+g' /etc/lighttpd/conf.d/pihole-admin.conf
install -m 0755 -o root -g root php-cgi-pihole /usr/local/bin/php-cgi-pihole
# Optional. If you want to use a hardened systemd service file instead of the shipped one from Pi-hole.
install -m 0644 -o root -g root pihole-FTL.systemd /etc/systemd/system/pihole-FTL.service
systemctl daemon-reload
```

## SELinux Policy Installation
```sh
# Optional compile the selinux module(see below) or install from here

# Install the SELinux policy module. Optionally compile it before hand to ensure proper compatibility (see below)
semodule -i pihole.pp
# Restore all the correct context labels
chmod u+x restore_contexts.sh && ./restore_contexts.sh
# Label Pi-hole port
semanage port -a -t pihole_port_t -p tcp 4711
# Start Pi-hole and Lighttpd
systemctl start lighttpd.service pihole-FTL.service 
# Ensure it's working in the proper confinement
ps auxZ | grep pihole
# Above should show that the binary and the php-cgi engine are running in pihole_t and pihole_cgi_script_t domains:
system_u:system_r:pihole_t:s0               pihole      /usr/bin/pihole-FTL
system_u:system_r:pihole_cgi_script_t:s0    lighttpd    /usr/bin/php-cgi
```

## How To Compile The Module Locally (Needed before installing)
Ensure you have the `policycoreutils-devel` package installed.
```sh
# Ensure you have the devel packages
dnf install policycoreutils-devel
# Copy relevant .if interface file to /usr/share/selinux/devel/include to expose them when building and for future modules. NOTE: Update this file if you make changes to the local version!
install -Dp -m 0644 -o root -g root pihole.if /usr/share/selinux/devel/include/myapplications/pihole.if
# Change to the directory containing the .if, .fc & .te files
cd pihole-selinux
make -f /usr/share/selinux/devel/Makefile pihole.pp && semodule -i pihole.pp
```

## Debugging and Troubleshooting

* If you're getting SELinux AVC permission errors, do: `setenforce 0` and then replicate the steps you took when something wasn't working and then the ausearch command below.
* Easy way to add in allow rules is the below command, then copy or redirect into the .te module. Rebuild and re-install.
* Don't forget to actually look at what is suggested. audit2allow will show the required allows - if you're confident, also check with `audit2allow -R` for any suggested interfaces to use. But beware this could be very coarse grained permissions or incorrect!
* Restarting pihole AND lighttpd services required when making policy edits. Don't forget after you've solved the issue to `setenforce 1` to reenable SELinux enforcing mode.

To report an issue; run and provide the output of(replace **time** with a time if you know when it occured to be more accurate. Otherwise us today/yesterday etc):
```sh
ausearch -m avc,user_avc,selinux_err -ts 12:00 | audit2allow
```

If you get a could not open interface info [/var/lib/sepolgen/interface_info] error. 
Ensure policycoreutils-devel is installed and/or run: `sepolgen-ifgen`  


[To provide a more verbose output that includes the path in the AVC deny:](https://danwalsh.livejournal.com/34903.html) Otherwise look at the inode in the AVC and do a `$ find -inum`
- Instructions based on CentOS Stream(path might be different for older versions or Fedora):
```sh
echo "-w /etc/shadow -p w" >> /etc/audit/rules.d/audit.rules
service auditd restart
```



## Compatibility Notes
Built on **CentOS Stream 9** (with testing also done on Fedora Server) at the time with:
```
systemd-252-18.el9.x86_64
libselinux-3.5-1.el9.x86_64
libselinux-utils-3.5-1.el9.x86_64
selinux-policy-38.1.23-1.el9.noarch
selinux-policy-targeted-38.1.23-1.el9.noarch
selinux-policy-devel-38.1.23-1.el9.noarch
```