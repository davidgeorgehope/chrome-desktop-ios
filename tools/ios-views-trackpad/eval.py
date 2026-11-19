import sys, json
sys.path.insert(0, '/tmp/uaecho')
import cdp
page=[t for t in cdp.targets() if t.get('type')=='page']
s=cdp.ws(page[0]['webSocketDebuggerUrl'])
r=cdp.call(s,1,'Runtime.evaluate',{'expression':sys.argv[1],'awaitPromise':True,'returnByValue':True})
print(json.dumps(r['result']['result'].get('value'))[:600])
