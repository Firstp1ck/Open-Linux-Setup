Press Shift + F10 to open the command prompt

### old method:
start ms-cxh:localonly

### new method:
- net user USERNAME * /add
- Type Password
- net localgroup administrators "USERNAME" /add
- net user "USERNAME" /active:yes
- net user "USERNAME" /expires:never
- net user "Administrator" /active:no
- net user "defaultUser0" /delete 
- Check with:
    - net user

- Now type regedit to open registry editor and navigate to:
    - Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE 

- Delete DefaultAccount registry entry keys
    - "DefaultAccountAction"
    - "DefaultAccountSAMName"
    - "DefaultAccountSID"

- Rename LaunchUserOOBE to SkipMachineOOBE
    - Set value to 1

- Shutdown and restart the computer
    - shutdown /r /t 0