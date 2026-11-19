import sys, json
sys.path.insert(0, '/tmp/uaecho')
import cdp
page=[t for t in cdp.targets() if t.get('type')=='page']
s=cdp.ws(page[0]['webSocketDebuggerUrl'])
r=cdp.call(s,1,'Input.dispatchMouseEvent',{'type':'mouseWheel','x':900,'y':500,'deltaX':0,'deltaY':600})
print(json.dumps(r)[:200])
import time; time.sleep(1.5)
r=cdp.call(s,2,'Runtime.evaluate',{'expression':'[scrollY, document.scrollingElement.scrollHeight, innerHeight]','returnByValue':True})
print(r['result']['result'].get('value'))
