@echo off
start /B cmd /c "cd /d C:\Users\HF\desktop\udhaar-app\backend && node server.js"
start /B cmd /c "cd /d C:\Users\HF\desktop\udhaar-app\frontend\build\web && npx serve -l 8080"
exit