function Invoke-NinjaGetNotification {
    param(
        # The title of the notification.
        [String]$Title = 'Software Updates in Progress',
        # The message to display in the notification.
        [String]$Message = 'Application updates are being installed. Please do not restart your computer.',
        # The message type to display.
        [String]$MessageType,
        # The app name to display in the notification.
        [String]$AppName = 'Software Updater',
        # The action to take when the notification is clicked.
        [String]$Action,
        # The body of the notification.
        [String]$Body,
        # The text for the button.
        [String]$ButtonText,
        # The action to take when the button is clicked.
        [String]$ButtonAction,
        # Show a dismiss button.
        [Switch]$DismissButton = $false,
        # Run in the user's context.
        [Switch]$UserContext = $false
    )
    if (($Script:NotificationLevel -eq 'Full') -or ($Script:NotificationLevel -eq 'SuccessOnly' -and $MessageType -eq 'Success') -or ($Script:NotificationLevel -eq 'ErrorOnly' -and $MessageType -eq 'Error') -or ($UserContext)) {
        # Create an XML toast template.
        [XML]$ToastTemplate = [System.Xml.XmlDocument]::new()
        $ToastTemplate.LoadXml('<?xml version="1.0" encoding="utf-8"?><toast></toast>')
        # Create the visual node in the XML.
        $Visual = $ToastTemplate.CreateElement('visual')
        # Create the binding node in the XML.
        $Binding = $ToastTemplate.CreateElement('binding')
        # Append the binding node to the visual node.
        $Visual.AppendChild($Binding) | Out-Null
        # Set the template attribute of the binding node.
        $Binding.SetAttribute('template', 'ToastGeneric') | Out-Null
        # Add the image to the toast template.
        $ImagePath = "$Script:InstallPath\resources\$MessageType.png"
        if (Test-Path -Path $ImagePath) {
            # Create the image node in the XML.
            $Image = $ToastTemplate.CreateElement('image')
            # Append the image node to the binding node.
            $Binding.AppendChild($Image) | Out-Null
            # Set the placement attribute of the image node.
            $Image.SetAttribute('placement', 'appLogoOverride') | Out-Null
            # Set the source attribute of the image node.
            $Image.SetAttribute('src', $ImagePath) | Out-Null
        }
        # Add the title to the toast template.
        if ($Title) {
            # Create the title node in the XML.
            $TitleNode = $ToastTemplate.CreateElement('text')
            # Create the title text node in the XML.
            $TitleTextNode = $ToastTemplate.CreateTextNode($Title)
            # Append the title text node to the title node.
            $TitleNode.AppendChild($TitleTextNode) | Out-Null
            # Append the title node to the binding node.
            $Binding.AppendChild($TitleNode) | Out-Null
        }
        # Add the message to the toast template.
        if ($Message) {
            # Create the message node in the XML.
            $MessageNode = $ToastTemplate.CreateElement('text')
            # Create the message text node in the XML.
            $MessageTextNode = $ToastTemplate.CreateTextNode($Message)
            # Append the message text node to the message node.
            $MessageNode.AppendChild($MessageTextNode) | Out-Null
            # Append the message node to the binding node.
            $Binding.AppendChild($MessageNode) | Out-Null
        }
        # Add the body to the toast template.
        if ($Body) {
            # Create a group node in the XML.
            $Group = $ToastTemplate.CreateElement('group')
            # Append the group node to the binding node.
            $Binding.AppendChild($Group) | Out-Null
            # Create a sub-group node in the XML.
            $SubGroup = $ToastTemplate.CreateElement('subgroup')
            # Append the sub-group node to the group node.
            $Group.AppendChild($SubGroup) | Out-Null
            # Create the body node in the XML.
            $BodyNode = $ToastTemplate.CreateElement('text')
            # Create the body text node in the XML.
            $BodyTextNode = $ToastTemplate.CreateTextNode($Body)
            # Append the body text node to the body node.
            $BodyNode.AppendChild($BodyTextNode) | Out-Null
            # Append the body node to the sub-group node. 
            $SubGroup.AppendChild($BodyNode) | Out-Null
            # Set the hint-style attribute of the body node.
            $BodyNode.SetAttribute('hint-style', 'body') | Out-Null
            # Set teh hint-wrap attribute of the body node.
            $BodyNode.SetAttribute('hint-wrap', 'true') | Out-Null
        }
        # Create the actions node in the XML.
        $Actions = $ToastTemplate.CreateElement('actions')
        # Add the first button to the toast template if required.
        if ($ButtonText) {
            # Create the first button node in the XML.
            $Button = $ToastTemplate.CreateElement('action')
            # Set the content attribute of the first button node.
            $Button.SetAttribute('content', $ButtonText) | Out-Null
            # Set the arguments attribute of the first button node.
            $Button.SetAttribute('arguments', $ButtonAction) | Out-Null
            # Append the first button node to the actions node.
            $Actions.AppendChild($Button) | Out-Null
            # If we have button actions add the arguments to the toast template.
            if ($ButtonAction) {
                # Set the arguments attribute of the button node.
                $Button.SetAttribute('arguments', $ButtonAction) | Out-Null
                # Set the activationType attribute of the button node.
                $Button.SetAttribute('activationType', 'Protocol') | Out-Null
            }
        }
        # Add the dismiss button to the toast template if required.
        if ($DismissButton) {
            # Create the dismiss button node in the XML.
            $Dismiss = $ToastTemplate.CreateElement('action')
            # Set the content attribute of the dismiss button node.
            $Dismiss.SetAttribute('content', '') | Out-Null
            # Set the arguments attribute of the dismiss button node.
            $Dismiss.SetAttribute('arguments', 'dismiss') | Out-Null
            # Set the activationType attribute of the dismiss button node.
            $Dismiss.SetAttribute('activationType', 'system') | Out-Null
            # Append the dismiss button node to the actions node.
            $Actions.AppendChild($Dismiss) | Out-Null
        }

        # Create the tag node for the application name.
        $Tag = $ToastTemplate.CreateElement('tag')
        # Create a text node for the application name.
        $TagTextNode = $ToastTemplate.CreateTextNode($AppName)
        # Append the text node to the tag node.
        $Tag.AppendChild($TagTextNode) | Out-Null
        # Append the visual node to the toast template.
        $ToastTemplate.LastChild.AppendChild($Visual) | Out-Null
        # Append the actions node to the toast template.
        $ToastTemplate.LastChild.AppendChild($Actions) | Out-Null
        # Append the tag node to the toast template.
        $ToastTemplate.LastChild.AppendChild($Tag) | Out-Null
        # If we have an on-click action add the arguments to the toast template.
        if ($OnClickAction) {
            # Set the activationType attribute of the toast template.
            $ToastTemplate.toast.SetAttribute('activationType', 'Protocol') | Out-Null
            # Set the launch attribute of the toast template.
            $ToastTemplate.toast.SetAttribute('launch', $OnClickAction) | Out-Null
        }
        # If we're running as SYSTEM we'll save the toast template as XML so the scheduled task can read it.
        if ($Script:RunAsSystem) {
            # Set the toast template path.
            $ToastTemplatePath = "$Script:InstallPath\Configuration\"
            # If the toast template path doesn't exist create it.
            if (-not (Test-Path $ToastTemplatePath)) {
                # Create the toast template path.
                New-Item -Path $ToastTemplatePath -ItemType Directory -Force | Out-Null
            }
            # Set the toast template file path.
            $ToastTemplateFile = "$ToastTemplatePath\ToastTemplate.xml"
            # Save the toast template as XML.
            $ToastTemplate.Save($ToastTemplateFile) | Out-Null
            #Run the scheduled task to notify conneted users
            Get-ScheduledTask -TaskName 'NinjaGet Notifier' -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
        } else {
            # Load the assemblies we need.
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
            [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
            # Prepare the XML payload.
            $ToastTemplateXml = [Windows.Data.Xml.Dom.XmlDocument]::new()
            # Load the toast template XML.
            $ToastTemplateXml.LoadXml($ToastTemplate.OuterXml)
            # Specify the app identifier.
            $AppId = 'NinjaGet.Notifications'
            # Prepare the toast notification.
            $ToastNotification = [Windows.UI.Notifications.ToastNotification]::new($ToastTemplateXml)
            # Bubble up the toast tag.
            $ToastNotification.Tag = $ToastTemplate.toast.tag
            # Create a toast notifier.
            $ToastNotifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
            # Show the toast notification.
            $ToastNotifier.Show($ToastNotification)
        }
        # Wait for the toast to display.
        Start-Sleep -Seconds 3
    }
}