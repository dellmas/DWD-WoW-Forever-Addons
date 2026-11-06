"""DWD-only addon updater. Standard-library Windows app; no GitHub login needed."""
from __future__ import annotations
import argparse, contextlib, ctypes, datetime as dt, hashlib, json, os
from pathlib import Path, PurePosixPath
import shutil, subprocess, sys, threading, time, urllib.parse, urllib.request, zipfile

VERSION = '1.0.0'
REPOSITORY = 'dellmas/DWD-WoW-Forever-Addons'
API_URL = 'https://api.github.com/repos/' + REPOSITORY + '/releases/latest'
ALLOWED = frozenset(('!DWD_Profiles_Loader','DWD_Profiles','DWD_Profiles_Recovery',
    'DWD_MobCount','DWD_PartyXP_Forever','DWD_TooltipMover','DWD_UpdaterStatus'))
DATA = Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'DWDAddonUpdater'
STARTUP_NAME = 'DWD Addon Updater.lnk'
CHECK_INTERVAL = 30 * 60
MAX_ARCHIVE = 20 * 1024 * 1024
MAX_EXPANDED = 60 * 1024 * 1024

def now(): return dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read_json(path, default=None):
    try: return json.loads(Path(path).read_text(encoding='utf-8'))
    except FileNotFoundError: return default

def write_json(path, data):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_name(path.name+'.tmp')
    temp.write_text(json.dumps(data,indent=2),encoding='utf-8');os.replace(temp,path)

def reparse(path):
    p=Path(path)
    return p.is_symlink() or (hasattr(p,'is_junction') and p.is_junction())

def under(path, parent):
    path=Path(path).absolute();parent=Path(parent).absolute()
    if not path.is_relative_to(parent) or path==parent: raise ValueError('Path escaped the managed directory')
    return path

def wow_root(path):
    p=Path(path).expanduser().absolute()
    if p.name.lower()=='addons': p=p.parent.parent
    elif p.name.lower()=='world of warcraft': p=p/'_forever_'
    if p.name.lower()!='_forever_' or not (p/'Wow.exe').is_file():
        raise ValueError('Choose the World of Warcraft _forever_ folder containing Wow.exe')
    if not (p/'Interface'/'AddOns').is_dir(): raise ValueError('Forever Interface/AddOns folder not found')
    for part in (p,p/'Interface',p/'Interface'/'AddOns'):
        if reparse(part): raise ValueError('The game/addon root cannot be a junction or symbolic link')
    return p

def detect_wow():
    guesses=[]
    for drive in 'CDEFGHIJKLMNOPQRSTUVWXYZ':
        for base in ('BattleNet Games/World of Warcraft','World of Warcraft','Games/World of Warcraft',
                     'Program Files (x86)/World of Warcraft','Program Files/World of Warcraft'):
            guesses.append(Path(drive+':/')/base/'_forever_')
    for p in guesses:
        if (p/'Wow.exe').is_file():
            try: return wow_root(p)
            except ValueError: pass
    return None

def wow_running():
    if os.name!='nt': return False
    # Read process names using Windows, without inspecting game memory or input.
    from ctypes import wintypes as w
    class Entry(ctypes.Structure):
        _fields_=[('size',w.DWORD),('usage',w.DWORD),('pid',w.DWORD),('heap',ctypes.c_size_t),
          ('module',w.DWORD),('threads',w.DWORD),('parent',w.DWORD),('priority',w.LONG),
          ('flags',w.DWORD),('exe',w.WCHAR*260)]
    k=ctypes.WinDLL('kernel32',use_last_error=True)
    k.CreateToolhelp32Snapshot.argtypes=[w.DWORD,w.DWORD];k.CreateToolhelp32Snapshot.restype=w.HANDLE
    k.Process32FirstW.argtypes=[w.HANDLE,ctypes.POINTER(Entry)];k.Process32FirstW.restype=w.BOOL
    k.Process32NextW.argtypes=[w.HANDLE,ctypes.POINTER(Entry)];k.Process32NextW.restype=w.BOOL
    k.CloseHandle.argtypes=[w.HANDLE]
    handle=k.CreateToolhelp32Snapshot(2,0)
    if handle==ctypes.c_void_p(-1).value: raise OSError('Unable to check whether WoW is running')
    try:
        entry=Entry();entry.size=ctypes.sizeof(entry)
        if not k.Process32FirstW(handle,ctypes.byref(entry)): raise OSError('Unable to read the process list')
        while True:
            if entry.exe.lower() in ('wow.exe','wowclassic.exe','wowt.exe','wowb.exe','wowclassicb.exe'):
                return True
            if not k.Process32NextW(handle,ctypes.byref(entry)): return False
    finally: k.CloseHandle(handle)

def safe_url(url):
    p=urllib.parse.urlsplit(url)
    prefix='/'+REPOSITORY+'/releases/download/'
    if p.scheme!='https' or p.netloc!='github.com' or not p.path.startswith(prefix) or p.query or p.fragment:
        raise ValueError('Unexpected update asset URL')
    return url

def fetch(url, limit, asset=False):
    if asset: safe_url(url)
    elif url!=API_URL: raise ValueError('Unexpected API URL')
    req=urllib.request.Request(url,headers={'User-Agent':'DWDAddonUpdater/'+VERSION,
        'Accept':'application/vnd.github+json' if not asset else 'application/octet-stream'})
    with urllib.request.urlopen(req,timeout=45) as response:
        data=response.read(limit+1)
    if len(data)>limit: raise ValueError('Download exceeds its size limit')
    return data

def latest():
    release=json.loads(fetch(API_URL,2*1024*1024))
    assets={a['name']:a for a in release['assets']}
    m=json.loads(fetch(assets['DWD-Updates.json']['browser_download_url'],2*1024*1024,True))
    validate_manifest(m)
    if m['release']!=release['tag_name']: raise ValueError('Release and manifest versions disagree')
    archive=assets['DWD-Only-Addons.zip']['browser_download_url']
    safe_url(archive)
    return m,archive

def validate_manifest(m):
    if m.get('schema')!=1 or m.get('game')!='forever' or m.get('interface')!=16001:
        raise ValueError('Unsupported DWD update manifest')
    if not isinstance(m.get('release'),str) or not m['release'].startswith('v'): raise ValueError('Bad release')
    if not isinstance(m.get('files'),dict) or not m['files']: raise ValueError('Missing file list')
    if not set(m.get('addons',[]))<=ALLOWED or set(m['addons'])!={PurePosixPath(p).parts[0] for p in m['files']}:
        raise ValueError('Manifest attempts to manage an unrelated addon')
    if len(m['files'])>1000: raise ValueError('Unexpected file count')
    import re
    if not re.fullmatch('[0-9a-f]{64}',m.get('sha256','')): raise ValueError('Bad archive checksum')
    for name,digest in m['files'].items():
        p=PurePosixPath(name)
        if '\\' in name or ':' in name or p.is_absolute() or '..' in p.parts or '.' in name.split('/') or len(p.parts)<2:
            raise ValueError('Unsafe archive path')
        if p.parts[0] not in ALLOWED or any(x.lower() in ('savedvariableslink','wtf') for x in p.parts):
            raise ValueError('Unmanaged or account-data path')
        if not re.fullmatch('[0-9a-f]{64}',digest): raise ValueError('Bad file checksum')
    for name in m['addons']:
        if name+'/'+name+'.toc' not in m['files']: raise ValueError('Missing addon TOC')

def unpack_verified(blob,m,dest):
    import io
    if len(blob)>MAX_ARCHIVE or hashlib.sha256(blob).hexdigest()!=m['sha256']:
        raise ValueError('Archive checksum does not match')
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        infos=z.infolist()
        if len(infos)!=len(m['files']) or len({i.filename for i in infos})!=len(infos):
            raise ValueError('Unexpected or duplicate archive members')
        if {i.filename for i in infos}!=set(m['files']): raise ValueError('Archive file list does not match')
        if sum(i.file_size for i in infos)>MAX_EXPANDED: raise ValueError('Expanded archive exceeds size limit')
        for info in infos:
            if (info.external_attr>>16)&0o170000==0o120000: raise ValueError('Symbolic links are not allowed')
            data=z.read(info)
            if hashlib.sha256(data).hexdigest()!=m['files'][info.filename]: raise ValueError('File checksum mismatch')
            p=under(Path(dest)/info.filename,dest);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)

def matches(folder,m,name):
    expected={p[len(name)+1:]:h for p,h in m['files'].items() if p.startswith(name+'/')}
    actual={}
    if not folder.is_dir() or reparse(folder): return False
    for base,dirs,files in os.walk(folder,followlinks=False):
        if any(reparse(Path(base)/d) for d in dirs): return False
        for file in files:
            p=Path(base)/file
            if reparse(p): return False
            actual[p.relative_to(folder).as_posix()]=sha(p)
    return actual==expected

@contextlib.contextmanager
def locked(path):
    Path(path).parent.mkdir(parents=True,exist_ok=True)
    f=open(path,'a+b')
    if f.seek(0,2)==0: f.write(b'0');f.flush()
    f.seek(0)
    try:
        if os.name=='nt':
            import msvcrt
            try: msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,1)
            except OSError: raise RuntimeError('Another DWD update check is running') from None
        yield
    finally:
        if os.name=='nt':
            import msvcrt
            with contextlib.suppress(OSError): f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,1)
        f.close()

class Updater:
    def __init__(self,data=DATA,process_check=wow_running,provider=latest,downloader=fetch):
        self.data=Path(data);self.data.mkdir(parents=True,exist_ok=True)
        self.process_check=process_check;self.provider=provider;self.downloader=downloader
    def status(self,**fields):
        value=read_json(self.data/'status.json',{})
        value.update(fields);value['updated']=now();write_json(self.data/'status.json',value)
        return value
    def log(self,message):
        p=self.data/'updater.log'
        if p.exists() and p.stat().st_size>1024*1024: os.replace(p,self.data/'updater.previous.log')
        with p.open('a',encoding='utf-8') as f: f.write(now()+' '+message+'\n')
    def paths(self):
        config=read_json(self.data/'config.json')
        if not config: raise ValueError('Install the updater and choose your Forever folder first')
        root=wow_root(config['wow_root'])
        return root,root/'Interface'/'AddOns'
    def recover(self):
        journal=read_json(self.data/'transaction.json')
        if not journal: return
        root,addons=self.paths()
        backup=Path(journal['backup']);under(backup,root/'Interface'/'DWDUpdaterBackups')
        if reparse(backup): raise ValueError('Unexpected backup link')
        failed=backup/'failed-new';failed.mkdir(exist_ok=True)
        for entry in reversed(journal['plan']):
            name=entry['name']
            if name not in ALLOWED: raise ValueError('Unmanaged addon in recovery plan')
            live=under(addons/name,addons);old=backup/name
            if old.exists():
                if live.exists(): live.rename(failed/name)
                old.rename(live)
            elif not entry['had_original'] and live.exists(): live.rename(failed/name)
        (self.data/'transaction.json').unlink()
        self.log('Rolled back an interrupted update; previous addon folders restored')
    def apply(self,m,stage,allow_running=False):
        root,addons=self.paths()
        selected=[n for n in m['addons'] if (addons/n).is_dir() or n=='DWD_UpdaterStatus']
        changed=[n for n in selected if not matches(addons/n,m,n)]
        if not changed: return False
        running=self.process_check()
        if running and not allow_running: return None
        structural=False
        for name in changed:
            expected={p[len(name)+1:] for p in m['files'] if p.startswith(name+'/')}
            existing=set()
            if (addons/name).is_dir():
                for base,dirs,files in os.walk(addons/name,followlinks=False):
                    dirs[:]=[d for d in dirs if not reparse(Path(base)/d)]
                    existing.update((Path(base)/f).relative_to(addons/name).as_posix() for f in files)
            if expected!=existing: structural=True
            old_toc=addons/name/(name+'.toc');new_toc=Path(stage)/name/(name+'.toc')
            def load_contract(path):
                if not path.is_file(): return []
                lines=path.read_text(encoding='utf-8-sig').splitlines()
                return [line.strip() for line in lines if line.strip() and
                    (not line.lstrip().startswith('#') or line.startswith(('## SavedVariables:',
                     '## SavedVariablesPerCharacter:','## Dependencies:','## RequiredDeps:','## LoadSavedVariablesFirst:')))]
            if load_contract(old_toc)!=load_contract(new_toc): structural=True
        for name in changed:
            if reparse(addons/name): raise ValueError('A managed addon root is a symbolic link or junction')
        stamp=dt.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        backup=root/'Interface'/'DWDUpdaterBackups'/stamp
        staging=root/'Interface'/'DWDUpdaterStaging'/stamp
        under(backup,root/'Interface'/'DWDUpdaterBackups');under(staging,root/'Interface'/'DWDUpdaterStaging')
        for parent in (backup.parent,staging.parent):
            if reparse(parent): raise ValueError('Unexpected staging/backup link')
        backup.mkdir(parents=True);staging.mkdir(parents=True)
        for name in changed:
            shutil.copytree(Path(stage)/name,staging/name)
            if not matches(staging/name,m,name): raise ValueError('Staged copy checksum mismatch')
        plan=[{'name':n,'had_original':(addons/n).exists()} for n in changed]
        write_json(self.data/'transaction.json',{'backup':str(backup),'plan':plan})
        try:
            for item in plan:
                if not allow_running and self.process_check(): raise RuntimeError('WoW started during installation; update rolled back')
                name=item['name'];target=under(addons/name,addons)
                if item['had_original']: target.rename(backup/name)
                (staging/name).rename(target)
            for name in changed:
                if not matches(addons/name,m,name): raise ValueError('Installed checksum mismatch')
            # Commit before notification. Backups remain for manual recovery.
            (self.data/'transaction.json').unlink()
        except Exception:
            self.recover();raise
        self.log('Installed '+m['release']+': '+', '.join(changed))
        message='DWD addons updated.'
        if running:
            message += ' Restart WoW to load added/removed files.' if structural else ' Type /reload in WoW to load the update.'
        else: message += ' Ready for the next WoW launch.'
        self.status(phase='updated',installed_release=m['release'],pending_release=None,
                    backup=str(backup),restart_required=running and structural,reload_required=running and not structural,
                    message=message)
        return True
    def check(self,requested=False):
        with locked(self.data/'check.lock'):
            root,addons=self.paths()
            if read_json(self.data/'transaction.json'):
                if self.process_check() and not requested: return self.status(phase='waiting',message='Recovery waits until WoW closes.')
                self.recover()
            m,url=self.provider();validate_manifest(m)
            self.status(last_check=now(),available_release=m['release'],last_error=None)
            selected=[n for n in m['addons'] if (addons/n).is_dir() or n=='DWD_UpdaterStatus']
            if all(matches(addons/n,m,n) for n in selected):
                (self.data/'pending.json').unlink(missing_ok=True)
                return self.status(phase='current',installed_release=m['release'],pending_release=None,message='DWD addons are up to date.')
            stage=self.data/'cache'/hashlib.sha256(json.dumps(m,sort_keys=True).encode()).hexdigest()
            if not all(matches(stage/n,m,n) for n in m['addons']):
                stage.mkdir(parents=True,exist_ok=True)
                blob=self.downloader(url,MAX_ARCHIVE,True)
                unpack_verified(blob,m,stage)
                if not all(matches(stage/n,m,n) for n in m['addons']): raise ValueError('Unpacked file verification failed')
            write_json(self.data/'pending.json',{'manifest':m,'stage':str(stage)})
            return self.apply_pending(allow_running=requested)
    def apply_pending(self,allow_running=False):
        pending=read_json(self.data/'pending.json')
        if not pending: return read_json(self.data/'status.json',{})
        m=pending['manifest'];validate_manifest(m)
        stage=Path(pending['stage']);under(stage,self.data/'cache')
        if not all(matches(stage/n,m,n) for n in m['addons']): raise ValueError('Pending update checksum mismatch')
        result=self.apply(m,stage,allow_running=allow_running)
        if result is None:
            return self.status(phase='waiting',pending_release=m['release'],message='Update downloaded. It will install after all WoW clients close.')
        (self.data/'pending.json').unlink(missing_ok=True)
        return read_json(self.data/'status.json',{})
    def watch(self):
        with locked(self.data/'watch.lock'):
            next_check=0
            while not (self.data/'disabled').exists():
                try:
                    if time.monotonic()>=next_check:
                        self.check();next_check=time.monotonic()+CHECK_INTERVAL
                    elif read_json(self.data/'pending.json') and not self.process_check():
                        with locked(self.data/'check.lock'): self.apply_pending()
                except Exception as e:
                    self.log(str(e));self.status(phase='error',last_error=str(e),message=str(e))
                    next_check=time.monotonic()+CHECK_INTERVAL
                time.sleep(15)

def shortcut(path,target,args=''):
    def quote(s): return "'"+str(s).replace("'","''")+"'"
    script='$w=New-Object -ComObject WScript.Shell;$s=$w.CreateShortcut('+quote(path)+');'
    script+='$s.TargetPath='+quote(target)+';$s.Arguments='+quote(args)+';$s.WindowStyle=7;$s.Save()'
    subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script],check=True,
        capture_output=True,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))

def install(path,data=DATA):
    root=wow_root(path);data=Path(data);data.mkdir(parents=True,exist_ok=True)
    if not getattr(sys,'frozen',False): raise ValueError('Use the packaged Windows executable to install')
    target=data/'DWDAddonUpdater.exe'
    if Path(sys.executable).resolve()!=target.resolve() and (not target.exists() or sha(target)!=sha(sys.executable)):
        shutil.copy2(sys.executable,target)
    config={'wow_root':str(root),'updater_version':VERSION,'installed':now()}
    write_json(data/'config.json',config)
    appdata=Path(os.environ['APPDATA'])/'Microsoft'/'Windows'/'Start Menu'/'Programs'
    shortcut(appdata/'Startup'/STARTUP_NAME,target,'--watch')
    shortcut(appdata/STARTUP_NAME,target)
    return config

def start_watcher(data=DATA):
    flags=getattr(subprocess,'CREATE_NO_WINDOW',0)|getattr(subprocess,'DETACHED_PROCESS',0)
    subprocess.Popen([str(Path(data)/'DWDAddonUpdater.exe'),'--watch'],creationflags=flags,close_fds=True)

def uninstall(data=DATA):
    # Disable future startup. The watcher notices this marker and exits.
    data=Path(data);(data/'disabled').write_text('disabled',encoding='utf-8')
    programs=Path(os.environ['APPDATA'])/'Microsoft'/'Windows'/'Start Menu'/'Programs'
    for p in (programs/'Startup'/STARTUP_NAME,programs/STARTUP_NAME): p.unlink(missing_ok=True)
    message='Automatic startup disabled. DWD addons, settings and backups are retained.'
    Updater(data).status(phase='disabled',message=message)
    return message

def gui():
    import tkinter as tk
    from tkinter import filedialog,messagebox
    window=tk.Tk();window.title('DWD Addon Updater');window.geometry('630x390');window.resizable(False,False)
    tk.Label(window,text='DWD Addon Updater',font=('Segoe UI',19,'bold')).pack(pady=(18,5))
    tk.Label(window,text='Updates only DWD addons for WoW Forever. Your settings stay yours.',font=('Segoe UI',10)).pack()
    config=read_json(DATA/'config.json',{});detected=detect_wow()
    folder=tk.StringVar(value=config.get('wow_root',str(detected) if detected else ''))
    panel=tk.Frame(window);panel.pack(fill='x',padx=24,pady=15)
    tk.Entry(panel,textvariable=folder,width=65).pack(side='left',fill='x',expand=True)
    tk.Button(panel,text='Browse',command=lambda:folder.set(filedialog.askdirectory(title='Choose _forever_') or folder.get())).pack(side='right',padx=(8,0))
    status=tk.StringVar(value='Automatic checks run at sign-in and every 30 minutes.\nUpdate Now installs immediately, even with WoW running.')
    tk.Label(window,textvariable=status,wraplength=575,justify='left',font=('Segoe UI',10)).pack(padx=24,pady=10,anchor='w')
    actions=tk.Frame(window);actions.pack(pady=12)
    def refresh():
        info=read_json(DATA/'status.json',{})
        if info:
            status.set(info.get('message','')+'\nInstalled: '+str(info.get('installed_release','waiting for first update'))
                +'\nLast checked: '+str(info.get('last_check','not yet')))
        window.after(2500,refresh)
    def run(fn):
        def worker():
            try: fn()
            except Exception as e: window.after(0,lambda error=str(e):messagebox.showerror('DWD updater',error))
        threading.Thread(target=worker,daemon=False).start()
    def do_install():
        (DATA/'disabled').unlink(missing_ok=True)
        install(folder.get());Updater().check(requested=True);start_watcher()
    tk.Button(actions,text='Install / Enable Auto Updates',command=lambda:run(do_install),padx=10,pady=6).pack(side='left',padx=4)
    tk.Button(actions,text='Update Now',command=lambda:run(lambda:Updater().check(requested=True)),padx=10,pady=6).pack(side='left',padx=4)
    tk.Button(actions,text='Disable Auto Updates',command=lambda:status.set(uninstall()),padx=10,pady=6).pack(side='left',padx=4)
    tk.Label(window,text='CurseForge and all non-DWD addons are left alone.\nBackups are kept in _forever_/Interface/DWDUpdaterBackups.',fg='#555555',font=('Segoe UI',9)).pack(pady=12)
    refresh();window.mainloop()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install',metavar='FOREVER_FOLDER');parser.add_argument('--check',action='store_true')
    parser.add_argument('--watch',action='store_true');parser.add_argument('--status',action='store_true')
    parser.add_argument('--uninstall',action='store_true')
    args=parser.parse_args()
    if args.install:
        (DATA/'disabled').unlink(missing_ok=True);result=install(args.install);result['status']=Updater().check(requested=True);start_watcher()
    elif args.check: result=Updater().check(requested=True)
    elif args.status: result=read_json(DATA/'status.json',{})
    elif args.uninstall: result=uninstall()
    elif args.watch: Updater().watch();return
    else: gui();return
    if sys.stdout: print(json.dumps(result,indent=2))

if __name__=='__main__':
    try: main()
    except Exception as error:
        DATA.mkdir(parents=True,exist_ok=True)
        Updater().log(str(error));Updater().status(phase='error',last_error=str(error),message=str(error))
        if sys.stderr: print(str(error),file=sys.stderr)
        sys.exit(1)
