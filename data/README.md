# Data contract

The analyses expect the original course artifact `FIFA2017_NL.RData`. The binary is deliberately excluded from this public repository because the supplied file contains no source citation, creator metadata, or redistribution licence. Public FIFA-derived datasets with similar columns exist, but that similarity does not establish the provenance or legal terms of this exact Eredivisie extract.

## Expected file

| Property | Required value |
|---|---|
| Filename | `FIFA2017_NL.RData` |
| Byte size | 25,532 bytes |
| SHA-256 | `a56a3065dba053436d0302cbf08a854c94d9c4cdeccdf3a7bf68daa99fdac540` |
| Serialized object | `fifa` |
| R class | `tbl_df`, `tbl`, `data.frame` |
| Dimensions | 488 rows × 35 columns |
| Clubs | 18 |
| Position counts | FW 179; Mid 78; Def 164; Gk 67 |

The ordered columns are:

```text
name, club, Position, crossing, finishing, heading_accuracy,
short_passing, volleys, dribbling, curve, free_kick_accuracy,
long_passing, ball_control, acceleration, sprint_speed, agility,
reactions, balance, shot_power, jumping, stamina, strength,
long_shots, aggression, interceptions, positioning, vision,
penalties, composure, marking, standing_tackle, sliding_tackle,
eur_value, eur_wage, eur_release_clause
```

`name` is character; `club` and `Position` are factors; the remaining 32 fields are integer. All 29 skill fields are complete and bounded between 0 and 100. `eur_release_clause` has 40 missing values; the other columns are complete.

## Local placement

If you have an authorized copy, either place it at the ignored path

```text
data/FIFA2017_NL.RData
```

or keep it anywhere outside the repository and export its path:

```bash
export FIFA2017_NL_PATH="/path/to/FIFA2017_NL.RData"
make verify-data
make run
```

Both R programs resolve paths relative to their own repository and honor `FIFA2017_NL_PATH`. A missing file produces an actionable error rather than attempting a download or silently substituting a different dataset.

## Analysis cohorts

- `src/01_pca_spca.R` requires complete skill, position, market-value, wage, and release-clause fields. It therefore analyzes 448 players.
- `src/02_manual_pmd.R` uses only the 29 complete skill columns and therefore analyzes all 488 players.

Do not publish a locally obtained copy unless its provenance and redistribution terms have been established independently.
