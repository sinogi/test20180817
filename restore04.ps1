<# 
説明
AzureBackupで取得したバックアップをリストアする際に可用性セットに組み込みたい場合は
PSでスクリプトを組む必要がありました。

もとのスクリプトは↓にあったものを参考にして少しだけカスタムしています
https://fsck.jp/?p=514
#>

#変数設定
#リソースグループ
$rg = "hogehoge"
#Recovery Services vault
$azbk = "AzureBakup01"
#元の仮想マシン名
$beforevm = "fuga-fuga"
#VHDファイルを配置するストレージアカウント
$strac = "fugatestvhd01"
#VM作成のためのJSONファイル配置先（ローカルファイルを指定）
$destination_dir = "C:\temp\"
$destination_path = $destination_dir + "vmconfig.json"
#可用性セット
$haset = "avail02"
#復元先仮想マシン名
$aftervm = "fuga-fuga03"
#復元先OSディスク名
$aftervm_os = $aftervm + "-osdisk"
#復元先NIC名
$nicName = $aftervm + "-nic"
#仮想ネットワーク名
$vnetName = "vnet03"
#サブネット指定
$subnet_num = "2"
#IPアドレス指定
$priIP = "10.3.0.21"


#コンテキストをRecovery Services vaultに設定する
$vault = Get-AzureRmRecoveryServicesVault -ResourceGroupName $rg -name $azbk | Set-AzureRmRecoveryServicesVaultContext

#仮想マシンを選択
$namedcontainer = Get-AzureRmRecoveryServicesBackupContainer -ContainerType AzureVM -Status Registered -FriendlyName $beforevm
$backupitem = Get-AzureRmRecoveryServicesBackupItem -Container $namedcontainer -WorkloadType AzureVM

#対象とする復元ポイントを探す
$startDate = (Get-Date).AddDays(-7)
$endDate = Get-Date
$rp = Get-AzureRmRecoveryServicesBackupRecoveryPoint -Item $backupItem -StartDate $startDate.ToUniversalTime() -EndDate $endDate.ToUniversalTime()

#復元ポイントを選択して、ディスクを復元する
$restorejob = Restore-AzureRmRecoveryServicesBackupItem -RecoveryPoint $rp[0] -StorageAccountName $strac -StorageAccountResourceGroupName $rg
Wait-AzureRmRecoveryServicesBackupJob -Job $restorejob -Timeout 43200

#復元ジョブの情報を元にJSONファイルを作成する
$restorejob = Get-AzureRmRecoveryServicesBackupJob -Job $restorejob
$details = Get-AzureRmRecoveryServicesBackupJobDetails -Job $restorejob
$properties = $details.properties
$storageAccountName = $properties["Target Storage Account Name"]
$containerName = $properties["Config Blob Container Name"]
$blobName = $properties["Config Blob Name"]
Set-AzureRmCurrentStorageAccount -Name $storageAccountName -ResourceGroupName $rg
Get-AzureStorageBlobContent -Container $containerName -Blob $blobName -Destination $destination_path

#復元する仮想マシンの設定をJSONファイルから読み込む
$obj = ((Get-Content -Path $destination_path -Raw -Encoding Unicode)).TrimEnd([char]0x00) | ConvertFrom-Json
$availabilitySet = Get-AzureRmAvailabilitySet -ResourceGroupName $rg -Name $haset
$vm = New-AzureRmVMConfig -VMSize $obj.'properties.hardwareProfile'.vmSize -VMName $aftervm -AvailabilitySetId $availabilitySet.Id

#ディスクの設定を追加する
Set-AzureRmVMOSDisk -VM $vm -Name $aftervm_os -VhdUri $obj.'properties.storageProfile'.osDisk.vhd.Uri -CreateOption "Attach"
$vm.storageProfile.OsDisk.OsType = $obj.'properties.storageProfile'.OsDisk.OsType

#NICの設定を追加する
$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rg
$nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rg -Location "japaneast" -SubnetId $vnet.Subnets[$subnet_num].Id  -PrivateIpAddress $priIP
$vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id

#仮想マシン復元を実行する
New-AzureRmVM -ResourceGroupName $rg -Location japaneast -vm $vm
