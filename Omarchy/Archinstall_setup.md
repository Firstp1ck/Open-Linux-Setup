| Section | Option |
| --- | --- |
| Mirrors and repositories | Select regions > Your country |
| Disk configuration | Partitioning > Default partitioning layout > Select disk (with space + return) |
| Disk > File system | btrfs (default structure: yes + use compression) |
| Disk > Disk encryption | Encryption type: LUKS + Encryption password + Partitions (select the one) |
| Hostname | Give your computer a name |
| Bootloader | Limine |
| Authentication > Root password | Set yours |
| Authentication > User account | Add a user > Superuser: Yes > Confirm and exit |
| Applications > Audio | pipewire |
| Network configuration | Copy ISO network config |
| Timezone | Set yours |

### Start omarchy script (Fork for Fuzzy-Menu Implementation)
- `eval "$(curl -fsSL https://raw.githubusercontent.com/Firstp1ck/omarchy-fuzzy-menu/refs/heads/master/boot.sh)"`