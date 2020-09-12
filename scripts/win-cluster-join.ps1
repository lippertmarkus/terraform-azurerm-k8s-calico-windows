# install manually as automatic install for "CurrentUser" fails
Install-Package -Scope AllUsers -Force 7Zip4PowerShell -Verbose

# copy kube-config and etcd-certs from primary node
mkdir C:\k
mkdir C:\pki
scp -oStrictHostKeyChecking=no -i C:\AzureData\CustomData.bin azadmin@primary:~/.kube/config C:\k\config
scp -oStrictHostKeyChecking=no -i C:\AzureData\CustomData.bin azadmin@primary:~/etcd/* C:\pki

# get installation script
Invoke-WebRequest https://docs.projectcalico.org/scripts/install-calico-windows.ps1 -OutFile c:\install-calico-windows.ps1

# modify installation script to set some more config params and automatically setup calico-kube-config for us
$search = "if (`$DownloadOnly"
$append = @"
SetConfigParameters -OldString 'ETCD_KEY_FILE = ""' -NewString 'ETCD_KEY_FILE = "c:\pki\server.key"'
SetConfigParameters -OldString 'ETCD_CERT_FILE = ""' -NewString 'ETCD_CERT_FILE = "c:\pki\server.crt"'
SetConfigParameters -OldString 'ETCD_CA_CERT_FILE = ""' -NewString 'ETCD_CA_CERT_FILE = "c:\pki\ca.crt"'
GetCalicoKubeConfig -SecretName 'calico-node'
"@
(Get-Content C:\install-calico-windows.ps1).Replace($search, "$append`n$search") | Set-Content C:\install-calico-windows.ps1

# run calico installation
c:\install-calico-windows.ps1 -KubeVersion "1.19.1" -Datastore "etcdv3" -EtcdEndpoints "https://primary:2379"

# install kubernetes services
cd c:\CalicoWindows\kubernetes
.\install-kube-services.ps1
Start-Service -Name kubelet
Start-Service -Name kube-proxy