// node scripts/lists.test.mts
import assert from 'node:assert/strict'
import { listFromJson } from '../src/main/lists.ts'

assert.deepEqual(listFromJson({ kind: 'apps', keys: ['git', 'git', 'vlc'] }, 'apps'), ['git', 'vlc'])
assert.deepEqual(listFromJson(['WPFInstallgit', 'WPFTweaksTelemetry'], 'apps'), ['git', 'WPFTweaksTelemetry'])
assert.deepEqual(listFromJson({ WPFTweaks: ['WPFTweaksTelemetry'], WPFInstall: ['WPFInstallGit'] }, 'tweaks'), ['WPFTweaksTelemetry'])
assert.deepEqual(listFromJson({ WPFInstall: ['WPFInstallGit'] }, 'apps'), ['Git'])
assert.deepEqual(listFromJson(['ok', '../evil', 'a b', 5, null], 'tweaks'), ['ok'])
assert.deepEqual(listFromJson(null, 'apps'), [])
assert.equal(listFromJson(Array.from({ length: 5000 }, (_, i) => `k${i}`), 'apps').length, 2000)
console.log('lists: ok')
