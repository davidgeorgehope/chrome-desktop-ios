#!/bin/bash
# Simulator-only mic test: launch echo page, getUserMedia + level meter + 3 s MediaRecorder.
U=${SIM_UDID:-booted}
pkill -x chrome_views_ios; sleep 1
cd ~/chromium-build/logs/views-m2
WAIT=${WAIT:-25} bash run-tvout.sh --no-first-run --no-default-browser-check --hide-crash-restore-bubble --remote-debugging-port=9333 '--remote-allow-origins=*' --use-fake-ui-for-media-stream $EXTRA 'http://127.0.0.1:8765/' >/tmp/tvout.out 2>&1
R=$(ls -td run/* | head -1)
grep -q "willConnect role=UIWindowSceneSessionRoleExternalDisplay" $R/stderr.txt || { xcrun simctl io $U screenConfig --display=TVOut power off >/dev/null 2>&1; sleep 2; xcrun simctl io $U screenConfig --display=TVOut power on >/dev/null 2>&1; sleep 10; echo replugged; }
timeout 60 python3 /tmp/uaecho/eval.py '(async()=>{try{const s=await navigator.mediaDevices.getUserMedia({audio:true});const t=s.getAudioTracks()[0];const ctx=new AudioContext();const an=ctx.createAnalyser();an.fftSize=2048;ctx.createMediaStreamSource(s).connect(an);const buf=new Float32Array(2048);let peak=0,sum=0,n=0;const chunks=[];const rec=new MediaRecorder(s);rec.ondataavailable=e=>chunks.push(e.data);rec.start(500);for(let i=0;i<30;i++){await new Promise(r=>setTimeout(r,100));an.getFloatTimeDomainData(buf);for(const x of buf){peak=Math.max(peak,Math.abs(x));sum+=x*x;n++}}rec.stop();await new Promise(r=>rec.onstop=r);const size=chunks.reduce((a,b)=>a+b.size,0);const devs=(await navigator.mediaDevices.enumerateDevices()).filter(d=>d.kind=="audioinput").map(d=>d.label);return {ok:true,label:t.label,state:t.readyState,settings:t.getSettings(),peak:Math.round(peak*10000)/10000,rms:Math.round(Math.sqrt(sum/n)*10000)/10000,recBytes:size,mime:rec.mimeType,inputs:devs}}catch(e){return {ok:false,err:String(e)}}})()'
echo "rc=$?"
pgrep -x chrome_views_ios >/dev/null && echo ALIVE || { echo DEAD; grep -m2 -E "FATAL|Received signal" $R/stderr.txt; }
xcrun simctl io $U screenshot --display=TVOut $R/mic-tvout.png >/dev/null 2>&1
xcrun simctl io $U screenshot --display=LCD $R/mic-phone.png >/dev/null 2>&1
echo $R
