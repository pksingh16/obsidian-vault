
# Install Wifi

```powershell
Install-WindowsFeature -Name Wireless-Networking

Start-Service -Name wlansvc
```

# Apply License

```powershell
DISM /Online /Set-Edition:ServerStandard /ProductKey:<license-key> /AcceptEula
```
