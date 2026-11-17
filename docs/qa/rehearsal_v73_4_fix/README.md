# Evidence: CON-423, v73.4 rehearsal tooling fixes

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-16 |
| Last modified | 2026-11-16 |
| Status | PROVISIONAL (section 11.4.290), host-only tests |

Machine output from the CON-423 fix, captured on the host on 2026-11-16. The
rehearsal report it answers has sha256
74ecd83f35174902d7732b966d0393dfad21c46beb72eabd486d1b54f4a0b3d5.

What each file shows:

- `tar_red.log` / `tar_green_final.log`: tests/release/test_tag_and_release.sh on the
  pre-fix script (403 pass, 37 fail) and on the final tree (440 pass, 0 fail).
- `rre_red.log` / `rre_green2.log`: tests/release/test_render_release_entry.sh, 46/17
  before and 65/0 after.
- `pvl_red.log` / `pvl_green.log`: tests/release/test_provisional_verification_lines.sh.
- `pvl_checker_red_realdb.txt` / `pvl_checker_green_realdb.txt`: the checker on the real
  tracker database before the D2 data (FAIL: CON-211, CON-235, CON-236 and CON-265 had no
  verification line, CON-190 and CON-191 lacked the checks field) and after (29 of 29
  pass); `pvl_checker_final.txt` is the run after CON-423 itself moved to Ready for testing (30 of
  30 pass).
- `census_green2.log`: tests/release/test_channel_census.sh, 99/0.
- `pin_diff2.txt`: the reviewed netgate pin diff (only tag_and_release.sh changed).
- `dedupe_search.txt`: the dedupe search done before the new items were added.
- `mut/`: one log per mutant (24 mutants, each killed by its property), the four stream
  summaries, and `control_final.log` (all 9 controls pass their suites,
  control_failures=0). `control.log` is the earlier control run from stream A.

No file here contains a token value. Each file was checked for the real values of
M3W_GITEA_TOKEN, GITHUB_TOKEN and GITLAB_TOKEN (0 files each) and for token-shaped
strings (0 files; a control needle matched).

## sha256

```
76c21d1a41331413697bba95f9a6b19223f8079de4af3bc473a0fe49156bce17  ./census_green2.log
581ea5be3241b010674e6be5621b19cf1bfb214453816177c9543c5531896714  ./dedupe_search.txt
b78a8549f5fb02429c17002c707c6967444b75672f162f82d6c0e31b50491d77  ./mut/CD1.log
b677d9b94a58d8193bc5dc828ae5628189e4722974d7f80b3a16f3ea361efec0  ./mut/CD2.log
1b5b66c056b7c14494acaa50bca8c0bd22b806002f3f4dac05f184afc0c68a8d  ./mut/CD3.log
683f2f136d243f199affac17cfedda0c204d5454f53e41dfebcbd643bde40442  ./mut/DP1.log
34f51c021e016da704cebdceffd4a08515abf8284fa3ce2b4bdca35d0d21c2a4  ./mut/DP2.log
41b91201592e83f0518cdd6f1c3c8fc2971953be9689b67eaaf5a7404de0f704  ./mut/DP3.log
fecc0198176a7c6e1c9360241a7b64d0c844c0b506a5467e30a3dcf5fcb1ab98  ./mut/DP4.log
96e7097e9cdc7731c76b23f083a688efb184a5789fa15e9b1898bafe1bda6b25  ./mut/DP5.log
2a74703a890325e0ce876703be426d89e2235e84f35fc79f0df5156ec4a32587  ./mut/DP6.log
15206798a9dea1e1670eadc11f9df5b3b4f53407a49663052320fd948c806d91  ./mut/DP7.log
423aed85e51c0c9396a799bd65ad9ee3002b36bda8d1dd4c2a74309a3fbdc93f  ./mut/DP8.log
3dbed75a1d9f2f47107b0301bb70d2d2cfe9f98f0b3fbb414f18218ab34bd2f7  ./mut/DR1.log
ae3de934063686181ae06bb83dc5ba308cb8bf5422314284a957287f1fd697e1  ./mut/DR2.log
07fa6476c922b629894e8b51335fa59368e8aba096d0b2a70d9024fbaae4f769  ./mut/DR3.log
ac91da140e8c8ed9239821af59c13d5ea433e021d9501eacac5f679096eb3b7b  ./mut/GP15.log
a765dfcc355f2cb0ec550a846007f8783203ab10dab097ffafb1731446de4d05  ./mut/GP16.log
eaf35abed097cb76fd5afb542b344e0d97881b982a72a1ff3d05c3dd4133d9bd  ./mut/GP21.log
5c17ab304a5d18eba916e7c419727964639f874c9850fc8b54028c132c0fa9f1  ./mut/RN1.log
5d4ab3f36742bb10c24b5d6544c5382b2eb0f651e7811e67e808c86c83e45528  ./mut/RN2.log
8009c3a6b0609f8a5801db3a422c47e48f0e23e87478d57f0a539df3489ea6f9  ./mut/RN3.log
d27780d3a05b1bb9663b566b5daaf607fa35c42b645856d5f0d4621cf9ff6548  ./mut/RN4.log
5a5715347ebe058fbb79e6c8b769c34e69cca7a8593029954fb4a0234efc8632  ./mut/RN5.log
a8419df1f10fbf8aab0ba57389ca53202c41f208bdbed11dfbe11c8f1e98eb53  ./mut/TPL1.log
14fba3741ce3d5852d5f7e285afcbb088782081de0d4f66e6d059b094bb1f42a  ./mut/U9.log
075b4c3f145329a39e4b67179be6e2e6bf34003559986ef77945cd65cfc51f20  ./mut/control.log
075b4c3f145329a39e4b67179be6e2e6bf34003559986ef77945cd65cfc51f20  ./mut/control_final.log
5c0f3cfcc91b97a891173dfafa2d2dd042875ebe32d378e8930c09acebfd4bc3  ./mut/stream_A.txt
22e25e6230f72c67015ee1e81fa1cf92b5686f7f7e39d7295701af723c9f04ba  ./mut/stream_B.txt
832247415641a4d07f9925191a629856e74f4665841da1692b5e1e0bfee54101  ./mut/stream_C.txt
fd318ef3922ceadf3a0853c117b93830c6bfcfec25644a3d59e4bb2ea1d70efa  ./mut/stream_D.txt
07bfa5974c1727c7594f94d12103156cb9944f1779e5f26bc5195b0657f74e6c  ./pin_diff2.txt
6851991af92f35a7f3d8052d60c4a583ce64bf931cec0f0a5317636d5b9fa2f5  ./pvl_checker_final.txt
ed6802f19d0a5d456b8ea98acfcf06c588f268a32c4650487bae1a1ead1e0d96  ./pvl_checker_green_realdb.txt
6001dfd2c248ceeb3d2379e4456401b6647a69992940c8954312a50e3ed2d6b9  ./pvl_checker_red_realdb.txt
b2266c4dc0e7215372bee0d64179da08673409b792a65cb7828b82e8b24a6042  ./pvl_green.log
b81dff4f3573654db892fc01ac2d4128d07598f5127871b7a11c7477860174fe  ./pvl_red.log
86a5b78743aae606de013dd54a48cefd760a10656260bf0e6dde768f389b4c1a  ./rre_green2.log
3fa2e5abd7c498c2f305ec53b65833b94c727ade6d93851bbc818c5e57a1bbc6  ./rre_red.log
348ce4bf05495cbdfae90b24bdf286446c169aa3626cff406d528fa800eec89b  ./tar_green_final.log
edd69c0f54297a637991d08621180e225743c8eec00d8fcba5fc9c042840a0e1  ./tar_red.log
```
