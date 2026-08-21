Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "cmd /c cd /d C:\Users\HF\desktop\udhaar-app\frontend\build\web && npx serve -l 8080", 0, False