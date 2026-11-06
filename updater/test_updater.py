import hashlib,io,json,os,sys,tempfile,unittest,zipfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parent))
import updater as u

def package(version='v-test',extra=False):
    files={'DWD_MobCount/DWD_MobCount.toc':b'## Interface: 16001\nDWD_MobCount.lua\n',
           'DWD_MobCount/DWD_MobCount.lua':b'new-code',
           'DWD_UpdaterStatus/DWD_UpdaterStatus.toc':b'## Interface: 16001\nMain.lua\n',
           'DWD_UpdaterStatus/Main.lua':b'print("status")'}
    if extra:files['DWD_MobCount/New.lua']=b'added'
    out=io.BytesIO()
    with zipfile.ZipFile(out,'w') as z:
        for name,data in files.items():z.writestr(name,data)
    blob=out.getvalue()
    manifest={'schema':1,'game':'forever','interface':16001,'release':version,
      'addons':['DWD_MobCount','DWD_UpdaterStatus'],'sha256':hashlib.sha256(blob).hexdigest(),
      'files':{n:hashlib.sha256(d).hexdigest() for n,d in files.items()}}
    return manifest,blob

class TestUpdater(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.base=Path(self.temp.name)
        self.root=self.base/'_forever_';self.root.mkdir();(self.root/'Wow.exe').write_bytes(b'test')
        self.addons=self.root/'Interface'/'AddOns';self.addons.mkdir(parents=True)
        self.mob=self.addons/'DWD_MobCount';self.mob.mkdir()
        (self.mob/'DWD_MobCount.lua').write_bytes(b'old-code')
        (self.mob/'DWD_MobCount.toc').write_bytes(b'## Interface: 16001\nDWD_MobCount.lua\n')
        self.other=self.addons/'Questie';self.other.mkdir();(self.other/'untouched').write_bytes(b'keep')
        self.settings=self.root/'WTF'/'Account';self.settings.mkdir(parents=True)
        (self.settings/'saved.lua').write_bytes(b'personal-settings')
        self.data=self.base/'updater';self.data.mkdir()
        u.write_json(self.data/'config.json',{'wow_root':str(self.root)})
        self.m,self.blob=package()
        self.running=False
        self.app=u.Updater(self.data,lambda:self.running,lambda:(self.m,'unused'),lambda *a:self.blob)
    def tearDown(self):self.temp.cleanup()
    def untouched(self):
        self.assertEqual((self.other/'untouched').read_bytes(),b'keep')
        self.assertEqual((self.settings/'saved.lua').read_bytes(),b'personal-settings')
    def test_update_backup_and_settings(self):
        result=self.app.check()
        self.assertEqual(result['phase'],'updated')
        self.assertEqual((self.mob/'DWD_MobCount.lua').read_bytes(),b'new-code')
        self.assertEqual((Path(result['backup'])/'DWD_MobCount'/'DWD_MobCount.lua').read_bytes(),b'old-code')
        self.untouched()
    def test_automatic_update_stages_while_running(self):
        self.running=True;result=self.app.check()
        self.assertEqual(result['phase'],'waiting')
        self.assertEqual((self.mob/'DWD_MobCount.lua').read_bytes(),b'old-code')
        self.assertTrue((self.data/'pending.json').is_file());self.untouched()
    def test_requested_update_installs_while_running(self):
        self.running=True;result=self.app.check(requested=True)
        self.assertEqual(result['phase'],'updated')
        self.assertEqual((self.mob/'DWD_MobCount.lua').read_bytes(),b'new-code')
        self.assertTrue(result['restart_required']) # New status-addon folder.
        self.untouched()
    def test_existing_file_update_only_needs_reload(self):
        self.app.check();(self.mob/'DWD_MobCount.lua').write_bytes(b'old-again')
        self.running=True;result=self.app.check(requested=True)
        self.assertTrue(result['reload_required']);self.assertFalse(result['restart_required'])
    def test_added_file_needs_restart_but_installs_now(self):
        self.app.check();self.m,self.blob=package(extra=True)
        self.running=True;result=self.app.check(requested=True)
        self.assertTrue(result['restart_required']);self.assertTrue((self.mob/'New.lua').is_file())
    def test_toc_contract_change_needs_restart(self):
        self.app.check()
        (self.mob/'DWD_MobCount.toc').write_bytes(b'## Interface: 16001\n## SavedVariables: NewDB\nDWD_MobCount.lua\n')
        self.running=True;result=self.app.check(requested=True)
        self.assertTrue(result['restart_required'])
    def test_current_release_clears_stale_pending(self):
        self.app.check();u.write_json(self.data/'pending.json',{'stale':True})
        self.app.check();self.assertFalse((self.data/'pending.json').exists())
    def test_restart_notice_survives_recheck_until_game_closes(self):
        self.running=True;self.app.check(requested=True)
        status=self.app.check();self.assertTrue(status['restart_required'])
        self.assertIn('Restart WoW',status['message'])
        self.running=False;status=self.app.check()
        self.assertFalse(status['restart_required']);self.assertFalse(status['reload_required'])
    def test_pending_applies_after_exit(self):
        self.running=True;self.app.check();self.running=False
        result=self.app.apply_pending();self.assertEqual(result['phase'],'updated')
        self.assertFalse((self.data/'pending.json').exists())
    def test_current_is_noop(self):
        first=self.app.check();second=self.app.check()
        self.assertEqual(second['phase'],'current');self.assertEqual(second['backup'],first['backup'])
    def test_corrupt_download_does_not_touch_game(self):
        self.blob=b'corrupted'
        with self.assertRaises(ValueError):self.app.check(requested=True)
        self.assertEqual((self.mob/'DWD_MobCount.lua').read_bytes(),b'old-code');self.untouched()
    def test_unmanaged_addon_manifest_rejected(self):
        self.m['addons'].append('Questie')
        with self.assertRaises(ValueError):self.app.check()
        self.untouched()
    def test_traversal_and_account_data_rejected(self):
        for name in ('DWD_MobCount/../../WTF/settings.lua','DWD_MobCount/SavedVariablesLink/a.lua',
                     'DWD_MobCount/C:/outside.lua','/DWD_MobCount/a.lua','DWD_MobCount\\a.lua'):
            m,_=package();m['files'][name]='0'*64
            with self.subTest(name=name),self.assertRaises(ValueError):u.validate_manifest(m)
    def test_archive_duplicate_rejected(self):
        stream=io.BytesIO(self.blob)
        with zipfile.ZipFile(stream,'a') as z:z.writestr('DWD_MobCount/DWD_MobCount.lua',b'evil')
        b=stream.getvalue();self.m['sha256']=hashlib.sha256(b).hexdigest()
        with self.assertRaises(ValueError):u.unpack_verified(b,self.m,self.base/'extract')
    def test_rollback_if_wow_starts_mid_update(self):
        checks=iter((False,False,True))
        self.app.process_check=lambda:next(checks)
        with self.assertRaises(RuntimeError):self.app.check()
        self.assertEqual((self.mob/'DWD_MobCount.lua').read_bytes(),b'old-code')
        self.assertFalse((self.addons/'DWD_UpdaterStatus').exists());self.untouched()
    def test_recovery_after_interrupted_folder_swap(self):
        backup=self.root/'Interface'/'DWDUpdaterBackups'/'test';backup.mkdir(parents=True)
        self.mob.rename(backup/'DWD_MobCount');self.mob.mkdir();(self.mob/'new').write_text('partial')
        u.write_json(self.data/'transaction.json',{'backup':str(backup),
          'plan':[{'name':'DWD_MobCount','had_original':True}]})
        self.app.recover()
        self.assertEqual((self.mob/'DWD_MobCount.lua').read_bytes(),b'old-code')
        self.assertTrue((backup/'failed-new'/'DWD_MobCount'/'new').exists());self.untouched()
    def test_missing_optional_addons_not_forced_back(self):
        self.app.check()
        self.assertFalse((self.addons/'DWD_Profiles').exists())
        self.assertFalse((self.addons/'Bartender4_Forever').exists())
    def test_only_official_release_asset_urls_allowed(self):
        u.safe_url('https://github.com/'+u.REPOSITORY+'/releases/download/v1/a.zip')
        for url in ('http://github.com/'+u.REPOSITORY+'/releases/download/v1/a.zip',
                    'https://example.com/a.zip','https://github.com/other/repo/releases/download/v1/a.zip'):
            with self.assertRaises(ValueError):u.safe_url(url)

if __name__=='__main__':unittest.main(verbosity=2)
