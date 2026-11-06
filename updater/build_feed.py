"""Build the DWD-only feed assets for a future public GitHub release."""
from pathlib import Path
import argparse,hashlib,json,os,zipfile
from updater import ALLOWED,validate_manifest,reparse

def build(addons,output,release):
    addons=Path(addons).resolve();output=Path(output).resolve();output.mkdir(parents=True,exist_ok=True)
    contents={}
    for name in sorted(ALLOWED):
        folder=addons/name
        if not folder.is_dir() or reparse(folder):raise ValueError('Missing or linked addon: '+name)
        for base,dirs,files in os.walk(folder,followlinks=False):
            if any(reparse(Path(base)/d) for d in dirs):raise ValueError('Feed must use portable addon copies without junctions')
            for file in files:
                path=Path(base)/file
                if reparse(path):raise ValueError('Feed cannot include symbolic links')
                contents[path.relative_to(addons).as_posix()]=path.read_bytes()
    archive=output/'DWD-Only-Addons.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for name,data in sorted(contents.items()):z.writestr(name,data)
    manifest={'schema':1,'game':'forever','interface':16001,'release':release,'addons':sorted(ALLOWED),
      'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
      'files':{n:hashlib.sha256(d).hexdigest() for n,d in contents.items()}}
    validate_manifest(manifest)
    (output/'DWD-Updates.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    return manifest

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--addons',required=True);p.add_argument('--output',required=True);p.add_argument('--release',required=True)
    args=p.parse_args();m=build(args.addons,args.output,args.release)
    print('Built',m['release'],'with',len(m['files']),'verified DWD files')
