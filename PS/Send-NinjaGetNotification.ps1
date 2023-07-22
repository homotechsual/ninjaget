$NinjaGetInstallPath = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\NinjaGet\' -Name InstallLocation
[xml]$NotificationXML = Get-Content "$NinjaGetInstallPath\Configuration\ToastTemplate.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
if (!($NotificationXML)) {
    break
}
# Load the assemblies we need.
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
# Prepare the XML payload.
$ToastTemplateXml = [Windows.Data.Xml.Dom.XmlDocument]::new()
# Load the toast template XML.
$ToastTemplateXml.LoadXml($NotificationXML.OuterXml)
# Specify the app identifier.
$AppId = 'NinjaGet.Notifications'
# Prepare the toast notification.
$ToastNotification = [Windows.UI.Notifications.ToastNotification]::new($ToastTemplateXml)
# Bubble up the toast tag.
$ToastNotification.Tag = $NotificationXML.toast.tag
# Create a toast notifier.
$ToastNotifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
# Show the toast notification.
$ToastNotifier.Show($ToastNotification)