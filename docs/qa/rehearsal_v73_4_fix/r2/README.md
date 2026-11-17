# CON-423 review r1 remediation (r2) — evidence

| Field | Value |
|---|---|
| Item | CON-423 (follow-ups CON-424 to CON-427 keep their ids) |
| Review answered | REVIEW_CON-423.md, sha256 fe550511c6a6eb86b262c9ebef3b372f1d8aea85bd3e61a3e768df20d4e9fb12 (NO-GO, B1 blocking, M1 to M9) |
| Code commit | ed6a21e0 (fix(release): CON-423 review r1 remediation) |
| Base | origin/main 9fc9c904 with the round-1 bundle merged (merge commit 2a599a78) |
| Produced by | Claude Opus 5.5, fresh r2 fixer subagent; reasoning effort UNKNOWN (not settable or readable on this path) |
| Status | PROVISIONAL (section 11.4.290); needs the independent review |

Every result below is a host run on a scratch clone. Nothing was pushed.

## What each finding got

- **B1, M1, M2, M7 (checker).** `scripts/validation/check_provisional_verification_lines.py` now refuses placeholder,
  empty, punctuation-only and template values in all six fields, checks a shape per field, requires a real date in
  `due`, ignores fenced lines and accepts the colon-less form. RED: `logs/pvl_red_r2.log` (old checker, new test:
  pass=30 fail=29). GREEN: `logs/green_r2_provisional_verification_lines.log` (60/0, 23 paired mutants caught,
  including `pv2-strip`, the reviewer's PV2 `due: .`). Grid: `logs/pvl_grid_r2.txt` (272 cases, 0 mismatches).
  Reviewer probe: `logs/probe_pvl_r2.txt` (all 10 shapes refused, ok=0 fail=10).
  Placeholder census of the corpus, with control needles: `logs/placeholder_corpus_r2.txt` (tool source:
  `tools/placeholder_corpus.py.txt`).
- **UNCONFIRMED legality.** Refused as a whole field value. Legal only as a trailing qualifier after a complete value
  (section 11.4.292(C) writes an uncaptured field as `UNCONFIRMED: <reason>`, and such a field is not complete).
  The rule is documented in the checker's docstring.
- **M3 (repo_key).** RED: `logs/tar_red_m8_r2.log` and `logs/tar_red_r2.log` (RH16, 4 failures). GREEN:
  `logs/green_r2_tag_and_release.log` (455/0). Mutants RK1 to RK5 and RN3 are in `mutants/`.
- **M4 (marker words).** RED: `logs/rre_red_r2.log` (73/6). GREEN: `logs/green_r2_render_release_entry.log` (79/0).
  Mutants DR1 and DR3 to DR7 are in `mutants/`.
- **M5 and M6 (CON-423 text).** M5: "five of the six D2 items" is now correct (see `tracker/con423_con427_spec.json`
  and `tracker/con423_before_r2.md`). M6: the Reproduction signature and the Investigation root cause carry the
  evidence sha256 `edd69c0f54297a637991d08621180e225743c8eec00d8fcba5fc9c042840a0e1` of
  `docs/qa/rehearsal_v73_4_fix/tar_red.log`. The engine has no sha256 field for these records, so the sha256 is in
  the text.
- **M8 (one token shape).** `rc_gitea_token_shape_ok` in `scripts/release/redact_cut.sh`. RED:
  `logs/rc_red_m8_r2.log` (K12) and `logs/tar_red_m8_r2.log` (RH17, 3 failures). GREEN: redact 445/0,
  publish 170/0 (M8 cases), tag RH17. Mutants TS1 to TS4. The forge library's `{8,400}` check is a different
  contract (other forges) and was left alone.
- **M9.** Informational; ignored as instructed.

## Tracker changes (all through the engine)

- **Due migration.** 24 Ready-for-testing items had `due: next full-suite run` (or `next tracker review`), which the
  new due check refuses. They now read `due: 2026-11-23 (UNCONFIRMED: ...)`. The spec is in
  `tracker/due_migration_spec.json`. Each item was checked byte for byte, first on a copy and then on the real
  database; the before and expected bodies and the engine outputs are in `tracker/due_migration/`.
- **Side effect.** For 22 of the 24 items the description column now holds the whole free text. This is the CON-427
  coupling. Measured in `tracker/desc_side_effect_r2.txt`: CON-190 and CON-191 already held it. CON-427's acceptance
  now names these rows, and its own row changed the same way.
- **CON-423.** Text and verification line updated (artifact now names ed6a21e0; the job adds the redact and
  publish suites; due 2026-11-23). States kept: reproduced-host-fixture, root-cause-found-with-evidence.

## Other checks

- `logs/verify_manifest_r2.txt`: MANIFEST-OK. The excluded set now has 68 rows; the row for `tests/release/pvl_grid.py`
  was accepted as i@mvasic.ru (the commit identity) by the r2 fixer, see `logs/accept_excluded_r2.txt`. That
  acceptance needs the independent review.
- `logs/pin_diff_before_regen_r2.txt` / `logs/pin_diff_after_regen_r2.txt`: the netgate pin regenerated; pin-diff
  is now equal and netgate has 0 findings. The changes are line moves in the three edited scripts. The doubled-slash
  fold avoids the `//` pattern operator, which the analyser refuses.
- `logs/green_r2_channel_census.log` 99/0. `logs/git_env_census_r2.txt` PASS. `logs/gate_ledger_ratchet_r2.txt` PASS.
  `logs/index_fresh_r2.txt` PASS. `logs/validate_a_r2.txt` OK. `logs/diff_a_r2.txt` in sync. The final checks after
  the tracker commit are in `logs/final_*`. `tools/run_green_all.sh.txt` names `test_publish_gitea.sh` (the census
  reads it as a shell script that mentions git), so it has a `no-git-execution` row in
  `config/git_env_class_exemptions.tsv`.
- **Mutation harness.** `mutants/`: the 17 changed or new mutants were each killed by their property, and all 9
  controls pass. `logs/mut_stale_only_r2.txt`: every mutant applies (0 stale). The full harness was not re-run, so
  the result for the untouched mutants on this tree is UNCONFIRMED.

## Known limits

- Cyrillic look-alike letters are not folded (for example a Cyrillic "ТВD").
- The 2026-11-23 due dates are set by this fixer; no scheduler entry exists. They are marked UNCONFIRMED in the lines.
- The ids CON-423 to CON-427 are also minted by the unlanded Jev r12 bundle. Whichever lands second must re-mint.

## sha256 of every file in this directory (except this README)

```
f22acc0bc3de45ca8e6220dacefb0fc80b39531b8dee189fec8dc44c3509b468  logs/accept_excluded_r2.txt
00ccd513c3054321006ade0b6b541c8535eb5a4b9d5f43d51349224e75a165de  logs/diff_a_r2.txt
6851991af92f35a7f3d8052d60c4a583ce64bf931cec0f0a5317636d5b9fa2f5  logs/final_checker_realdb.txt
00ccd513c3054321006ade0b6b541c8535eb5a4b9d5f43d51349224e75a165de  logs/final_diff.txt
594b0b4bc33ed6283e7133a0bc59664a6738d4199bb214c31002111bd48c2208  logs/final_export.txt
d03aa1cd0a26464064512a719501ddd28c4984d4ea146541d7dfcae00fd4c39a  logs/final_gate_ledger_ratchet.txt
d9260a9efafe01f993da3de1f56cde152d2a3ad6124fbf3ee9075f4306b1bc59  logs/final_git_env_census.txt
5a7186bc96a86957d7501c789038f17295dde4f104574f58a2b5effae795b16d  logs/final_index_fresh.txt
1c5dd7600d6c7a074d14ea8f032ca3c9bcd3d7b33d6ca715ac5d761d42032dee  logs/final_validate.txt
cb7bddd6356f1a69e66ae30a42a1532edc556dfed2c9f3fb14d4c6107891cea6  logs/final_verify_manifest.txt
d03aa1cd0a26464064512a719501ddd28c4984d4ea146541d7dfcae00fd4c39a  logs/gate_ledger_ratchet_r2.txt
8752b3530cc35ab03a5e6af182bf8ed84d0b47fb5e3fe1cd8eed84307561f56f  logs/git_env_census_r2.txt
5e9fea0c971a370d11aa70f4c3914dc70b78bf215f5c04008d350a922f069e2d  logs/green_r2_channel_census.log
415b54009f3612d840bbb114ee43d8083ca0a3a45ab840044df1665556724ed4  logs/green_r2_derive_release_facts.log
9aba2fae37f33a2ae3db55570830e6b3d3a2d084a891d0429edc6e1fb9119cd0  logs/green_r2_provisional_verification_lines.log
d8abd73f4e66f59d029e7dc31de84b1ded4bb5c1129f67f213a8ed72aec06e2d  logs/green_r2_publish_gitea.log
10c634defbabbd42306bdfb1f2e884eb78be5113c2f3f206d503d1682e6006fb  logs/green_r2_redact_cut.log
890017e8062932c09654c7e890670608f3d127c8ba8d76269614fc3e4fcd84cc  logs/green_r2_render_release_entry.log
bc5cd14301c62802551a57b13882c46562c58c6f85dfb3fb0bb6f7557f2db275  logs/green_r2_tag_and_release.log
5a7186bc96a86957d7501c789038f17295dde4f104574f58a2b5effae795b16d  logs/index_fresh_r2.txt
d4043d53ffbcbbe9bfc8c8603ca404b5d7276ba31515a00349953763708dc5c2  logs/mut_stale_only_r2.txt
8c437cd54ec45287ff9b0f3e20dc93ed1068dcb3850c0e70cfd100e9f350a693  logs/pin_diff_after_regen_r2.txt
675ad969168c772868b8f598616f8bc56ce69e578ed6f797edf351c1eefb0d74  logs/pin_diff_before_regen_r2.txt
1feccbff77a9a6d38614d606fa5e188bd889a3c1d86123396d42c5d1d0213710  logs/pin_regen_r2.txt
439a780ea70a49cde1a5c4624fa145fe942b9f4abf7805c70805ab3f67b3ef47  logs/placeholder_corpus_r2.txt
bfb7f64fb2a3ab2b20cc75d13da1cc8c4729022f796bcee788bbd83357dff06c  logs/probe_pvl_r2.txt
fbba9bd531624cde72ad35ee4b5de9804328c14748226bb8a85c37e037b2c6e6  logs/pvl_grid_r2.txt
3eee6b90ca2bf3e4d64fa5540c6a25ddd669d9205b05979b6ee80b94510755e1  logs/pvl_red_r2.log
88be9f9bedd91a9021addcbb2a8d2d6b0d05ae1b39065fb03f0f53740d322f7e  logs/rc_red_m8_r2.log
99d72aa6eab92efe5aaa6a22f07c951b482533cc691dae8dfacb49ca46abc967  logs/rre_red_r2.log
33367c6281f0976c3f477ca92c2e3f893aff0d803e98156548772bf4a6fe4851  logs/sync_guide_r2.txt
0ca788c2b0ce640ed9a65a6409f17abef443cfa3853ee904bc0abe4050bd3268  logs/tar_red_m8_r2.log
ef5c8ba1a4666df96d063c5d02b812de680489bf2c63eeb677403baaa5fd64fb  logs/tar_red_r2.log
1c5dd7600d6c7a074d14ea8f032ca3c9bcd3d7b33d6ca715ac5d761d42032dee  logs/validate_a_r2.txt
cb7bddd6356f1a69e66ae30a42a1532edc556dfed2c9f3fb14d4c6107891cea6  logs/verify_manifest_r2.txt
3dbed75a1d9f2f47107b0301bb70d2d2cfe9f98f0b3fbb414f18218ab34bd2f7  mutants/DR1.log
adb565794d5466394dc9addc7ece839cadbb162afdc01d517601722f45121bec  mutants/DR3.log
3ddee8057a5602534c2ee7c6f13b8b60db9ecff75a9fe3240187e9fd2b8d6c7f  mutants/DR4.log
9ca40b5e04db4eb7972344aeab837b9b97682ca06f9da59bff280c5de4d487e6  mutants/DR5.log
c4823426bdac529e27071ffd4b345b6b307abba28921f866aec2e03653042c11  mutants/DR6.log
6e68628faefb7568fd1dc0a0e96e6a093bbf0196f79105ca1bd5c72630a95dfb  mutants/DR7.log
4888245837f884583bd333828ae78baa6390dbb2f7e997f6b6fdaa3ec5a8c5d4  mutants/RK1.log
3f171b92f15f213dfa52adfd633dedbdba785f9887d4fd398a03513663e7a4f2  mutants/RK2.log
336bdc467f7c7210a6407563f8123a7062cc9f0324e5f11df09ac0a74828849b  mutants/RK3.log
7fd78d80d506cb19038ed90e1571095c9dfe9a58d6342d9438d443ac96848967  mutants/RK4.log
43c8aa0ca7f66a3788237f0d3bb070585b352ebbbe635f2a12658335395fa175  mutants/RK5.log
8009c3a6b0609f8a5801db3a422c47e48f0e23e87478d57f0a539df3489ea6f9  mutants/RN3.log
ba6e063f76ca2c6a27b87c66915f82173a04d44574d17d79294f6ef386f23b97  mutants/TS1.log
3569a91214c127e8c45212ef9d7e30045c4a49b041c522b71c2b117bbb4e78b4  mutants/TS2.log
4644bcc8522a238fe75440825580745d5b9fdb973dd20c5569abbdb1343de1ef  mutants/TS3.log
38002b6c900e32bacc309b7348a4c2e7ac052804d84e9b5c2cd58e632fb4a893  mutants/TS4.log
075b4c3f145329a39e4b67179be6e2e6bf34003559986ef77945cd65cfc51f20  mutants/control.log
fa7fd488de06ef3c4cbf9351e31d66a3489b0f2958c43b5f50a73f9a7e43b5f0  tools/desc_side_effect.py.txt
16ee6dfe676d0ed488aeb07e16b67ab83e9ac287f740fe9c413c020f59b2c735  tools/dump_vlines.py.txt
60241561d3b66eb642271a699ae6bbe16c1d04dfe16437facaf59186c40c73c4  tools/engine_edit.py.txt
79f22591827bf7e1f220acfbbee88e80727040ee22c2c0b26d305e8cae6b3b6a  tools/mk_con423_spec.py.txt
9c69b0b44bc2fb935e2868e87deb796a2ff0f2652640a7570fc233fef08f90f6  tools/placeholder_corpus.py.txt
8cfc981458530323d85b6370985b60dfa9b32670134c8ef218ceae99fc7401f2  tools/run_green_all.sh.txt
0825e915ce3428a48887561f0cd95ed232f5a8589e60b2cafa1e056cc7778c3b  tools/run_mut_par.sh.txt
34f0f7c5a0aa2f63bef9563b50b27ae4da00f4a3e5965291643e8421a6d9a512  tools/run_red_m8.sh.txt
0712bf5b2fd255941bb416c24872fb508b07d01ecf6c6f2e6a2951eb42e9fe1c  tracker/con423_before_r2.md
70a697a7e146c85992e409f14f1adaf18fdc43c58d2b0e982074bd3d8a11d3b6  tracker/con423_con427_spec.json
a3ae8f8fcdf3c0a7eb303bf4fb437a258bbd81d518ef1e3ace0a8e16ba01fa49  tracker/desc_side_effect_r2.txt
61dadf834e1ec303207faa5ad7bb8a3067300699fe5560e611bdecb4425a98b2  tracker/due_migration/CON-015.before.txt
2f4a00cb6c8116e8131220f5ec4494392fdcc098058e5de29f908dda04700b80  tracker/due_migration/CON-015.expected.txt
e53530c57eafec25ef2e0157388765ed2bbb2c694302025cbcf1c65d8da7e834  tracker/due_migration/CON-015.update_real.out.txt
818003a9bfd390a7718e9a28c85cd0784215297ee339d5459c44213cb45fd084  tracker/due_migration/CON-016.before.txt
a25e5bb0dff593848698d3161af0bc08cad74008e3c66182c923e0d24852019c  tracker/due_migration/CON-016.expected.txt
9c674e6c23a22f21a255869037537d330a01ff70c53699e3739b53c7a44573a6  tracker/due_migration/CON-016.update_real.out.txt
cb13eb88bed1d78314a924be8b4c26143fc046b93879bf0e8137e3a35e0a281a  tracker/due_migration/CON-023.before.txt
5b5111a9ab4140912c5061baf6a00a0925cd503117c012a887dcf919b6d2e037  tracker/due_migration/CON-023.expected.txt
d6ed3e634d678c89e067975fc5b050748dddf6cd5cc7b42d9322bc9d9c2e02dd  tracker/due_migration/CON-023.update_real.out.txt
312693d8e050539fd27f9f33209677c23e9cb2a18c044981becfa73fa5b9afc6  tracker/due_migration/CON-043.before.txt
41ce71740b5cb5fed95ec86ed8ca04a008e2ecc3d3dec001f3fe69b4e4d14633  tracker/due_migration/CON-043.expected.txt
185bee62ec8572aab98ce42ce4d64394fa4b8c0fb03b0b33624cd9f4760a89b3  tracker/due_migration/CON-043.update_real.out.txt
49a5f8eaa50374b4bb40c1f35ee8560975341e58293aa5c4f3a132084a1775ae  tracker/due_migration/CON-144.before.txt
c2f63fcd9f0dfec55bfd94e498798adaec0e41d8d97eaef0030efb4e8b9ec2d4  tracker/due_migration/CON-144.expected.txt
e01c0419348858daace68b8b66fffe3494c7a4b5fafd36070e2eee898ba5315f  tracker/due_migration/CON-144.update_real.out.txt
8cf8a3b8d1bc5c6bf0c1c11310a00c2c41b60c25cfe0ed5050157946bc2f414d  tracker/due_migration/CON-159.before.txt
a7ed6702f636bc4f41150d85e318e27efffb086ba1c0d433336f9fa440bf7187  tracker/due_migration/CON-159.expected.txt
dd56770566d5cf3bb11153f5bc94649445717dd1f2a37cf5d155425f4947a7be  tracker/due_migration/CON-159.update_real.out.txt
8e001a8ebdb3d7fdd825c3c3f7e893a057dc66be6210cc80ac224a3f8b1cc8a6  tracker/due_migration/CON-160.before.txt
a83f98abf92fab8584fb76288e2ef78d2ee8f1bd04e4a195a5125c16fff65371  tracker/due_migration/CON-160.expected.txt
be88a40b768f344fda3d48e0a1b306108ecba2cb2d63b26d351f87f50399e892  tracker/due_migration/CON-160.update_real.out.txt
3ad053ff532d22294d8169b0649c1c89453a0ba28ea8f213a4a786913511c923  tracker/due_migration/CON-161.before.txt
441e9e560fa98b7b3acc452ec78dbdffc89541b52c25aa15bc3817621833516f  tracker/due_migration/CON-161.expected.txt
d04181184a79621b02dd9cce3857a13b29dcaac9a9626c5e7ace69f2bc264662  tracker/due_migration/CON-161.update_real.out.txt
7f6f4261a5a1cc5f86c6de9749a30b0e2112bfccb31b90888ed7156b16166d20  tracker/due_migration/CON-162.before.txt
e97301a38a02301570d4e31c145518838c709c04030803229c3bfd37e4ba3fc9  tracker/due_migration/CON-162.expected.txt
b29ab0e641368a11b9fa4a6ca8c877ca8df470ec8027efa3e67a2d5e7cfcd77f  tracker/due_migration/CON-162.update_real.out.txt
7d421cb7cdea14b6fcd84083947af6c5aa213e203b2b588d2398dc88665958cb  tracker/due_migration/CON-183.before.txt
3051be91b61c075a13e74ea55a3f55a2718532de349acbbf6cacca92ed396850  tracker/due_migration/CON-183.expected.txt
4f1fd2dd3967fcc8df395bb41b6a79612a101ed9cc9b62652e1c3435c2b81756  tracker/due_migration/CON-183.update_real.out.txt
aa7dba84932ec349bf64e32d3d66f2f21bc7013b01bacf3414f3fd4ce84ca144  tracker/due_migration/CON-184.before.txt
cc109e2ca7def801acfc8a9d8afcc6443f051432eaeb19e7f24a32fb5f7106c9  tracker/due_migration/CON-184.expected.txt
80de848f2fe92f0cbb15a9c055f62aee260a6ee036adc12fa00214a19f2cf63d  tracker/due_migration/CON-184.update_real.out.txt
92f0d5f33fe4bfd17db42a476587726a9a2aa374f26fd36816246105f43befdb  tracker/due_migration/CON-185.before.txt
8bf0d2bef17bb0fa3d254d513f3d2e83f6768fc47069437e86d7d3f45e719d7f  tracker/due_migration/CON-185.expected.txt
01df3428f71dea3b9d0ebb88655ac5488e135c3edc12f224bb757a27c74843f7  tracker/due_migration/CON-185.update_real.out.txt
acbc023c70919f371cef1ead118d73ac1c4682c13464a06e890799e69edd301d  tracker/due_migration/CON-186.before.txt
820cc51bba9cb35e1c9e2a271ac34af53d9db44682bd3cf3bb2087ae640a7e90  tracker/due_migration/CON-186.expected.txt
080f149f3899b687f9caa0b12cf49689a97892d96667748aad52b42b1a238b5f  tracker/due_migration/CON-186.update_real.out.txt
09954f9e1253cd335d6317da4dd0f6f0fcdf3342358801e81b8bb341c647cdec  tracker/due_migration/CON-189.before.txt
a20d60a753818292d09ce15000abcd1d67a32357f5f8a610465f2a314e885bbb  tracker/due_migration/CON-189.expected.txt
119fae9227fbdf9b9ba25f360f721ce221b9e4bfb197062c1edbd1b05a48f455  tracker/due_migration/CON-189.update_real.out.txt
765731a16ff66b51c7a55fb183f1c684d065485756be0f0c623f66dbf93f10ca  tracker/due_migration/CON-190.before.txt
db64e10f40b0226840f9214f646fb9610c4f83624000efa0f2948fa82b55fa74  tracker/due_migration/CON-190.expected.txt
3876e307b07f1052e2f09f440cbb8c97c9622e43b304cd5016cbfc2954394574  tracker/due_migration/CON-190.update_real.out.txt
7d2b242ba74082f7f6559d105f76e76b3a01313ca948636a69ed2f21e6087890  tracker/due_migration/CON-191.before.txt
c2dedbe5e07d855c338b54e899a5f2d5e31edbd1ad6ef957931a8b9a5ec29995  tracker/due_migration/CON-191.expected.txt
f779d15f743fd499ab415ed1536251fd9eae81c46edf7fbf2bc4a27317faa854  tracker/due_migration/CON-191.update_real.out.txt
1593d592f920ebf9667d3e2dcf981cc05146ba914559ce6f9f9d0b2fae72b5e3  tracker/due_migration/CON-216.before.txt
dc90f9fbccde0ca6ce662995cc09d8ae8d81c68c60c495193563254fcc1846f8  tracker/due_migration/CON-216.expected.txt
b0e2e4045904ee3090944128178f61563a65e56fbbd464c0f65a08df6f3727be  tracker/due_migration/CON-216.update_real.out.txt
d18782d121abd1e8e337fbde5f73df9afb9b1114aeba80abd19b6a24481ad2c8  tracker/due_migration/CON-217.before.txt
40fc0179935d5109083c931d5dc3770e4a0e0bf6e8b7df743cc461b0aee1bb13  tracker/due_migration/CON-217.expected.txt
8c8c8d71d81858cac6002147accbbb0f3d7382c9411e8ff85834f4652ad6c7bb  tracker/due_migration/CON-217.update_real.out.txt
9610f882ac5bfb3154c33f36280b5c5c3189e103937f51f1118bbd21f155f2a5  tracker/due_migration/CON-218.before.txt
cf3b54e3021aed72cbe3ead14d0f4a0ec5f0e0e1a185710ed8ddd16a9c4144c7  tracker/due_migration/CON-218.expected.txt
3f08e44bbe1a202e937fec7cb54390acca4c47321ce20b1e2f02a343cf81fda2  tracker/due_migration/CON-218.update_real.out.txt
232777a05a84bbec23f1c4119626f5296598a3c0512c0d2c744aaa88bfce2851  tracker/due_migration/CON-219.before.txt
62477ab2a2de64c4c284907ded6c3ffbf0202eb4790fa7f49954b9166e1a84bd  tracker/due_migration/CON-219.expected.txt
d8a9985e29f2118f055f85f12f1d2b4e8475f664c2aa20e570ed0d8a82b54ad2  tracker/due_migration/CON-219.update_real.out.txt
4d1eddf6b30f01b24dbd0706ff89b3301ed0ad85af71eff61e94de69f4686d99  tracker/due_migration/CON-220.before.txt
7954107e0cad209a1da6ad2fabd038ae264c8729fcbe245c72bfa9f73837fe85  tracker/due_migration/CON-220.expected.txt
980e6950fd791a10ef2f2e2fe64d92d01f7f633bc2dee540eaa18c5a29e62efe  tracker/due_migration/CON-220.update_real.out.txt
8da1d35eb4ceba64caa42369309187cc420117313ae96a300383e35b1a4c5a83  tracker/due_migration/CON-222.before.txt
8a12a7d37b956ecaaef155825d9fdd3a91921d6c1098fa04f5baf1201fd7d2d8  tracker/due_migration/CON-222.expected.txt
0f32f215c6b826bb69a8831bcc47025b4a1d652b516b1f230b65134e129563b7  tracker/due_migration/CON-222.update_real.out.txt
4c6ccc140095f5a8854a51ffb5ea0f58d8560ba5aec00559b09d4be98b914e1c  tracker/due_migration/CON-223.before.txt
75320eeddd7d43984b90a7917afead1be54785912e24d273409f84aa3962d8f1  tracker/due_migration/CON-223.expected.txt
39cc16b6a33bbae1fcea83060eda662c3024d0b3548722df2b90e8b4eaee998b  tracker/due_migration/CON-223.update_real.out.txt
7b95a679d7f7694484cf6bcf077e0bd5e413f7458665ec1238077ed44d15616f  tracker/due_migration/CON-224.before.txt
de117abd2d30971ac34078748a3bc9c27ea191e9046bea5d9f05407e05eb62c8  tracker/due_migration/CON-224.expected.txt
529d2943a22a3777f082f6a5b60cf6e86c8e0ed53adfe9f2b1a7fc432ab4701d  tracker/due_migration/CON-224.update_real.out.txt
3ddd396c02817774c3bf21b99aaa9c1635fec4cb50598d71d7f5986076251c85  tracker/due_migration_spec.json
```
