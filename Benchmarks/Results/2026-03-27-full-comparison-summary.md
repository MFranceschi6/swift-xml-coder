# 2026-03-27 Full Comparison Summary

Sources:
- `Benchmarks/Results/2026-03-27-internal-baseline.txt`
- `Benchmarks/Results/2026-03-27-post-encoder-tail-streaming.txt`

Method:
- Time uses p50 `Time (wall clock)`.
- Memory is reported as both p50 `Malloc (total)` and p50 `Memory (resident peak)`.
- Negative deltas are better for time and memory.
- `Malloc (total)` is the stronger memory signal here.
- `Memory (resident peak)` is order-sensitive inside a long monolithic benchmark run, so treat its deltas as informative but weaker than `Malloc (total)`.

## Internal: Baseline vs post `encodeTreeToData` tail streaming

### Main effect on encode

| Benchmark | Time p50 | Delta | Malloc p50 | Delta | Resident peak p50 | Delta |
|:--|:--|--:|:--|--:|:--|--:|
| `Encode/10KB` | `692 us -> 630 us` | `-9.0%` | `4600 -> 4595` | `-0.1%` | `253 M -> 658 M` | `+160.1%` |
| `Encode/100KB` | `6910 us -> 5960 us` | `-13.7%` | `45 K -> 45 K` | `+0.0%` | `251 M -> 722 M` | `+187.6%` |
| `Encode/1MB` | `68 ms -> 58 ms` | `-14.7%` | `451 K -> 451 K` | `+0.0%` | `268 M -> 939 M` | `+250.4%` |
| `Encode/Rich/10KB` | `608 us -> 575 us` | `-5.4%` | `3816 -> 3812` | `-0.1%` | `229 M -> 882 M` | `+285.2%` |
| `Encode/Rich/100KB` | `5939 us -> 5153 us` | `-13.2%` | `37 K -> 37 K` | `+0.0%` | `302 M -> 980 M` | `+224.5%` |
| `Encode/Rich/1MB` | `59 ms -> 51 ms` | `-13.6%` | `372 K -> 373 K` | `+0.3%` | `267 M -> 577 M` | `+116.1%` |
| `Encode/Rich/10MB` | `594 ms -> 527 ms` | `-11.3%` | `3733 K -> 3735 K` | `+0.1%` | `450 M -> 363 M` | `-19.3%` |

Reading:
- The patch improves real `encode` latency in a stable `5%` to `15%` band.
- `Malloc (total)` is effectively flat, which matches the implementation: less tail accumulation, not a new end-to-end tree construction strategy.
- `Resident peak` moves too much to treat as causal in this run format.

### Control benchmarks

| Benchmark | Time p50 | Delta | Malloc p50 | Delta | Resident peak p50 | Delta |
|:--|:--|--:|:--|--:|:--|--:|
| `StreamWrite/10KB` | `296 us -> 299 us` | `+1.0%` | `3465 -> 3465` | `+0.0%` | `483 M -> 679 M` | `+40.6%` |
| `StreamWrite/100KB` | `3082 us -> 3095 us` | `+0.4%` | `34 K -> 34 K` | `+0.0%` | `443 M -> 479 M` | `+8.1%` |
| `StreamWrite/1MB` | `31 ms -> 30 ms` | `-3.2%` | `342 K -> 342 K` | `+0.0%` | `323 M -> 497 M` | `+53.9%` |
| `StreamWrite/10MB` | `307 ms -> 299 ms` | `-2.6%` | `3420 K -> 3420 K` | `+0.0%` | `358 M -> 869 M` | `+142.7%` |
| `Canonicalize/StreamEvents/1KB` | `67 us -> 75 us` | `+11.9%` | `653 -> 653` | `+0.0%` | `249 M -> 828 M` | `+232.5%` |
| `Canonicalize/StreamEvents/10KB` | `603 us -> 608 us` | `+0.8%` | `6116 -> 6116` | `+0.0%` | `161 M -> 377 M` | `+134.2%` |
| `Canonicalize/StreamEvents/100KB` | `5738 us -> 5652 us` | `-1.5%` | `61 K -> 61 K` | `+0.0%` | `237 M -> 666 M` | `+181.0%` |
| `Canonicalize/Tree/1KB` | `90 us -> 91 us` | `+1.1%` | `758 -> 758` | `+0.0%` | `154 M -> 64 M` | `-58.4%` |
| `Canonicalize/Tree/10KB` | `820 us -> 815 us` | `-0.6%` | `7293 -> 7293` | `+0.0%` | `224 M -> 679 M` | `+203.1%` |
| `Canonicalize/Tree/100KB` | `8339 us -> 8331 us` | `-0.1%` | `73 K -> 73 K` | `+0.0%` | `245 M -> 499 M` | `+103.7%` |

Reading:
- The controls stay roughly flat on time and exactly flat on `Malloc (total)`.
- That makes the encode improvement look localized rather than accidental suite-wide drift.

## External: SwiftXMLCoder vs XMLCoder

### Encode

| Size | SwiftXMLCoder time | XMLCoder time | Delta | SwiftXMLCoder malloc | XMLCoder malloc | Delta | SwiftXMLCoder RSS | XMLCoder RSS | Delta |
|:--|:--|:--|--:|:--|:--|--:|:--|:--|--:|
| `10KB` | `642 us` | `1190 us` | `-46.1%` | `4597` | `5745` | `-20.0%` | `53 M` | `120 M` | `-55.8%` |
| `100KB` | `5992 us` | `12 ms` | `-50.1%` | `45 K` | `58 K` | `-22.4%` | `48 M` | `120 M` | `-60.0%` |
| `1MB` | `59 ms` | `120 ms` | `-50.8%` | `451 K` | `577 K` | `-21.8%` | `122 M` | `124 M` | `-1.6%` |
| `10MB` | `591 ms` | `1191 ms` | `-50.4%` | `4509 K` | `5821 K` | `-22.5%` | `228 M` | `204 M` | `+11.8%` |

Reading:
- Encode is the clearest win in the whole report: about `2x` faster with about `20%` lower malloc.

### Decode: Tree vs XMLCoder

| Size | SwiftXMLCoder Tree time | XMLCoder time | Delta | SwiftXMLCoder Tree malloc | XMLCoder malloc | Delta | SwiftXMLCoder Tree RSS | XMLCoder RSS | Delta |
|:--|:--|:--|--:|:--|:--|--:|:--|:--|--:|
| `10KB` | `548 us` | `652 us` | `-16.0%` | `4371` | `4075` | `+7.3%` | `120 M` | `120 M` | `+0.0%` |
| `100KB` | `5403 us` | `6287 us` | `-14.1%` | `43 K` | `40 K` | `+7.5%` | `120 M` | `121 M` | `-0.8%` |
| `1MB` | `54 ms` | `64 ms` | `-15.6%` | `432 K` | `397 K` | `+8.8%` | `66 M` | `112 M` | `-41.1%` |
| `10MB` | `530 ms` | `668 ms` | `-20.7%` | `4325 K` | `4015 K` | `+7.7%` | `275 M` | `287 M` | `-4.2%` |

Reading:
- Tree decode is the fastest decode path against `XMLCoder`.
- The tradeoff is clear too: it wins on time, but uses about `7%` to `9%` more malloc than `XMLCoder`.

### Decode: SAX vs XMLCoder

| Size | SwiftXMLCoder SAX time | XMLCoder time | Delta | SwiftXMLCoder SAX malloc | XMLCoder malloc | Delta | SwiftXMLCoder SAX RSS | XMLCoder RSS | Delta |
|:--|:--|:--|--:|:--|:--|--:|:--|:--|--:|
| `10KB` | `596 us` | `652 us` | `-8.6%` | `2671` | `4075` | `-34.5%` | `41 M` | `120 M` | `-65.8%` |
| `100KB` | `5710 us` | `6287 us` | `-9.2%` | `26 K` | `40 K` | `-35.0%` | `42 M` | `121 M` | `-65.3%` |
| `1MB` | `57 ms` | `64 ms` | `-10.9%` | `259 K` | `397 K` | `-34.8%` | `62 M` | `112 M` | `-44.6%` |
| `10MB` | `582 ms` | `668 ms` | `-12.9%` | `2586 K` | `4015 K` | `-35.6%` | `154 M` | `287 M` | `-46.3%` |

Reading:
- SAX decode is still faster than `XMLCoder`.
- It is also the best memory story against `XMLCoder`, with roughly `35%` lower malloc.

### Decode summary vs XMLCoder

| Size | Fastest SwiftXMLCoder path | Fastest SwiftXMLCoder time | XMLCoder time | Delta | Lowest-malloc SwiftXMLCoder path | Lowest SwiftXMLCoder malloc | XMLCoder malloc | Delta |
|:--|:--|:--|:--|--:|:--|:--|:--|--:|
| `10KB` | `Tree` | `548 us` | `652 us` | `-16.0%` | `SAX` | `2671` | `4075` | `-34.5%` |
| `100KB` | `Tree` | `5403 us` | `6287 us` | `-14.1%` | `SAX` | `26 K` | `40 K` | `-35.0%` |
| `1MB` | `Tree` | `54 ms` | `64 ms` | `-15.6%` | `SAX` | `259 K` | `397 K` | `-34.8%` |
| `10MB` | `Tree` | `530 ms` | `668 ms` | `-20.7%` | `SAX` | `2586 K` | `4015 K` | `-35.6%` |

## SwiftXMLCoder: Tree vs SAX

Note:
- There is no true apples-to-apples `Tree vs SAX` benchmark for `Codable` encode in this suite.
- The direct comparisons here are for decode and raw parse.

### Decode: Tree vs SAX

Delta is `Tree` relative to `SAX`.

| Size | Tree time | SAX time | Delta | Tree malloc | SAX malloc | Delta | Tree RSS | SAX RSS | Delta |
|:--|:--|:--|--:|:--|:--|--:|:--|:--|--:|
| `10KB` | `548 us` | `596 us` | `-8.1%` | `4371` | `2671` | `+63.6%` | `120 M` | `41 M` | `+192.7%` |
| `100KB` | `5403 us` | `5710 us` | `-5.4%` | `43 K` | `26 K` | `+65.4%` | `120 M` | `42 M` | `+185.7%` |
| `1MB` | `54 ms` | `57 ms` | `-5.3%` | `432 K` | `259 K` | `+66.8%` | `66 M` | `62 M` | `+6.5%` |
| `10MB` | `530 ms` | `582 ms` | `-8.9%` | `4325 K` | `2586 K` | `+67.2%` | `275 M` | `154 M` | `+78.6%` |

Reading:
- Tree decode is consistently faster than SAX decode.
- SAX decode is consistently better on memory, especially on `Malloc (total)`, by roughly one third.
- So the split is clean: `Tree` for best decode speed, `SAX` for best decode memory profile.

### Raw parse: Tree vs SAX

Delta is `TreeParse` relative to `SAXParse`.

| Size | TreeParse time | SAXParse time | Delta | TreeParse malloc | SAXParse malloc | Delta | TreeParse RSS | SAXParse RSS | Delta |
|:--|:--|:--|--:|:--|:--|--:|:--|:--|--:|
| `10KB` | `203 us` | `132 us` | `+53.8%` | `2038` | `92` | `+2115.2%` | `868 M` | `858 M` | `+1.2%` |
| `100KB` | `1964 us` | `1213 us` | `+61.9%` | `20 K` | `680` | `+2841.2%` | `846 M` | `812 M` | `+4.2%` |
| `1MB` | `19 ms` | `13 ms` | `+46.2%` | `204 K` | `6599` | `+2991.2%` | `796 M` | `667 M` | `+19.3%` |
| `10MB` | `199 ms` | `120 ms` | `+65.8%` | `2045 K` | `66 K` | `+2998.5%` | `583 M` | `920 M` | `-36.6%` |

Reading:
- On raw parser performance, SAX is the clearly cheaper path.
- Tree parsing is much slower and much more allocation-heavy because it is materializing structure instead of just walking events.
- This section is useful mostly as a reminder that `TreeParse` and `SAXParse` serve different goals, not as a sign that one should replace the other.

## Foundation comparisons

### Raw SAX parse: Foundation `XMLParser` vs SwiftXMLCoder `XMLStreamParser`

| Size | Foundation time | SwiftXMLCoder time | Delta | Foundation malloc | SwiftXMLCoder malloc | Delta | Foundation RSS | SwiftXMLCoder RSS | Delta |
|:--|:--|:--|--:|:--|:--|--:|:--|:--|--:|
| `10KB` | `100 us` | `132 us` | `+32.0%` | `92` | `92` | `+0.0%` | `75 M` | `858 M` | `+1044.0%` |
| `100KB` | `962 us` | `1213 us` | `+26.1%` | `680` | `680` | `+0.0%` | `102 M` | `812 M` | `+696.1%` |
| `1MB` | `9011 us` | `13 ms` | `+44.3%` | `6603` | `6599` | `-0.1%` | `89 M` | `667 M` | `+649.4%` |
| `10MB` | `101 ms` | `120 ms` | `+18.8%` | `115 K` | `66 K` | `-42.6%` | `91 M` | `920 M` | `+911.0%` |
| `100MB` | `1029 ms` | `1238 ms` | `+20.3%` | `1242 K` | `656 K` | `-47.2%` | `200 M` | `745 M` | `+272.5%` |

Reading:
- Foundation still wins on raw SAX parse latency.
- `Malloc (total)` is flat on small inputs and better for SwiftXMLCoder on very large ones.
- The RSS deltas here are heavily distorted by suite order, so do not use them for a product claim.

### Tree parse: Foundation tree parse vs SwiftXMLCoder tree parse

| Size | Foundation time | SwiftXMLCoder time | Delta | Foundation malloc | SwiftXMLCoder malloc | Delta | Foundation RSS | SwiftXMLCoder RSS | Delta |
|:--|:--|:--|--:|:--|:--|--:|:--|:--|--:|
| `10KB` | `296 us` | `203 us` | `-31.4%` | `1601` | `2038` | `+27.3%` | `96 M` | `868 M` | `+804.2%` |
| `100KB` | `2832 us` | `1964 us` | `-30.6%` | `15 K` | `20 K` | `+33.3%` | `141 M` | `846 M` | `+500.0%` |
| `1MB` | `28 ms` | `19 ms` | `-32.1%` | `151 K` | `204 K` | `+35.1%` | `117 M` | `796 M` | `+580.3%` |
| `10MB` | `303 ms` | `199 ms` | `-34.3%` | `1506 K` | `2045 K` | `+35.8%` | `154 M` | `583 M` | `+278.6%` |

Reading:
- SwiftXMLCoder is clearly ahead on tree parse time.
- The speedup comes with a higher malloc footprint, about `27%` to `36%` in this run.
- Again, RSS is order-sensitive and should not be used without rerunning these cases in isolation.

## Short takeaways

- The new tail-streaming encode path is worth keeping: real encode latency improved by roughly `5%` to `15%` while `Malloc (total)` stayed flat.
- Against `XMLCoder`, SwiftXMLCoder is very strong:
  - encode is about `2x` faster and about `20%` lower on malloc
  - tree decode is the fastest path
  - sax decode is the most memory-efficient path
- Against Foundation:
  - Foundation still wins raw SAX parsing latency
  - SwiftXMLCoder wins tree parse latency by roughly `31%` to `34%`
  - malloc is a tradeoff story, not a universal win
