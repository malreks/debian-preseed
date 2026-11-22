# Physical class data -> frozen installation plan. POSIX awk, no execution.
BEGIN { FS="\t"; OFS="\t"; limit=20000; next_repo=0 }
function fail(message) { print "fatal: class installation plan: " message > "/dev/stderr"; bad=1; exit 2 }
function listed(list,value, words,count,i) {
  count=split(list,words,","); for(i=1;i<=count;i++) if(words[i]==value) return 1
  return 0
}
function add(ref, words,count,i) {
  if(active[ref]) fail("class dependency cycle")
  if(selected[ref]) return
  if(!(ref in known)) fail("unknown registered class")
  if(!listed(arches[ref],architecture)) fail("unavailable class architecture")
  if(families[ref]!="all" && families[ref]!=family) fail("class crosses role family")
  active[ref]=1; count=split(requires[ref],words,",")
  for(i=1;i<=count;i++) if(words[i]!="") add(words[i])
  if(profile_codex_only!="true" && profile_codex_only!="false") fail("Codex profile policy requires a boolean")
  codex_enabled=(family=="server" && profile_codex_only=="true") || ("role/server/devops" in selected) || ("role/desktop/medium" in selected) || ("role/desktop/full" in selected)
  # Feature fragments are selected as a consequence of a role.  The fragment
  # itself is still active while its own record is being resolved, so applying
  # the role test again here would report a false self-cycle.  Keep the
  # resolver's real active-stack cycle detection for every other edge.
  if(codex_enabled && ref!="fragments/codex.cfg") add("fragments/codex.cfg")
  if(profile_whisper_enable!="true" && profile_whisper_enable!="false") fail("Whisper profile policy requires a boolean")
  if(profile_llama_enable!="true" && profile_llama_enable!="false") fail("Llama profile policy requires a boolean")
  if(family=="server" && profile_whisper_enable=="true" && ref!="fragments/whisper.cfg") add("fragments/whisper.cfg")
  if(family=="server" && profile_llama_enable=="true" && ref!="fragments/llama.cfg") add("fragments/llama.cfg")
  active[ref]=0; selected[ref]=1; order[++classcount]=ref
}
function list_answer(question) {
  return question=="pkgsel/include" || question=="base-installer/includes" || question=="base-installer/excludes" || question=="anna/choose_modules" || question=="modules" || question=="modules-udeb"
}
function merge_answer(row, key,value,words,count,i,slot,field,identity) {
  if(answer_owner[row]=="d-i" && answer_question[row] ~ /^apt-setup\/local[0-9]+\//) {
    # CUDA-legacy's explicit authentication exception is owned by its selected
    # apt-setup/pre-pkgsel hooks, never by the generic local-repository generator.
    if(answer_class[row]=="optional/cuda-legacy" && ("optional/cuda-legacy" in selected)) return
    slot=answer_question[row]; sub(/^apt-setup\/local/,"",slot); sub(/\/.*/,"",slot)
    field=answer_question[row]; sub(/^apt-setup\/local[0-9]+\//,"",field)
    identity=answer_class[row] SUBSEP slot
    if(!(identity in repo_seen)) { repo_seen[identity]=1; repo_order[++repo_count]=identity }
    if(!((identity SUBSEP field) in repo_fields_seen)) {repo_fields_seen[identity,field]=1; repo_fields[identity,++repo_fields_count[identity]]=field}
    repo_type[identity,field]=answer_type[row]; repo_value[identity,field]=answer_value[row]
    return
  }
  if(answer_question[row]=="pkgsel/include" && answer_type[row]!="seen") return
  key=answer_question[row] SUBSEP (answer_type[row]=="seen")
  if(key in ordinary_seen) {
    if(ordinary_owner[key]!=answer_owner[row] || ordinary_type[key]!=answer_type[row]) fail("answer owner/type conflict")
  } else {
    ordinary_seen[key]=1; ordinary_order[++ordinary_count]=key
    ordinary_owner[key]=answer_owner[row]; ordinary_question[key]=answer_question[row]; ordinary_type[key]=answer_type[row]
  }
  value=answer_value[row]
  if(list_answer(answer_question[row]) && answer_type[row]!="seen") {
    count=split(value,words,/[[:space:],]+/)
    for(i=1;i<=count;i++) if(words[i]!="" && !list_words[key,words[i]]++)
      ordinary_value[key]=ordinary_value[key] (ordinary_value[key]=="" ? "" : " ") words[i]
  } else ordinary_value[key]=value
}
function emit_answers(j,k,row,key,identity,repository,field,previous,i,policy) {
  for(j=1;j<=classcount;j++) for(k=1;k<=answer_count[order[j]];k++) merge_answer(answer_rows[order[j],k])
  for(j=1;j<=ordinary_count;j++) {
    key=ordinary_order[j]
    print "answer",ordinary_owner[key],ordinary_question[key],ordinary_type[key],ordinary_value[key]
  }
  for(j=1;j<=repo_count;j++) {
    identity=repo_order[j]; repository=repo_value[identity,"repository"]
    if(repository=="") fail("APT source block has no repository")
    if(repository in repository_seen) {
      previous=repository_seen[repository]
      for(i=1;i<=repo_fields_count[identity];i++) {
        field=repo_fields[identity,i]; if(field=="comment") continue
        if(repo_type[identity,field]!=repo_type[previous,field] || repo_value[identity,field]!=repo_value[previous,field]) fail("APT repository authentication or policy conflict")
      }
      for(i=1;i<=repo_fields_count[previous];i++) {
        field=repo_fields[previous,i]; if(field=="comment") continue
        if(!((identity SUBSEP field) in repo_fields_seen)) fail("APT repository policy field missing")
      }
      continue
    }
    repository_seen[repository]=identity
    for(i=1;i<=repo_fields_count[identity];i++) {
      field=repo_fields[identity,i]
      print "answer","d-i","apt-setup/local" next_repo "/" field,repo_type[identity,field],repo_value[identity,field]
    }
    next_repo++
  }
  print "answer","d-i","pkgsel/include","string",package_list
}
NR>limit { fail("class data exceeds record bound") }
$2!=suite { next }
$1=="class" { if(known[$3]++) fail("duplicate class data"); requires[$3]=$4; conflicts[$3]=$5; arches[$3]=$6; families[$3]=$7; next }
$1=="pkg" { packages[$3]=packages[$3] $4 ","; next }
$1=="answer" {
  if(NF!=7) fail("invalid compiled answer record")
  row=++answers_total; answer_class[row]=$3; answer_owner[row]=$4; answer_question[row]=$5; answer_type[row]=$6; answer_value[row]=$7
  answer_rows[$3,++answer_count[$3]]=row; next
}
$1=="stage" {
  row=++stagecount; stageclass[row]=$3; stageid[row]=$4; phase[row]=$5
  provider[row]=$6; after[row]=$7; before[row]=$8; next
}
END {
  if(bad) exit 2
  requested_count=split(roles,requested_roles," ")
  if(requested_count<1) fail("at least one role class is required")
  for(i=1;i<=requested_count;i++) {
    ref="role/" requested_roles[i]
    if(!(ref in known) || requested[ref]++) fail("unregistered or duplicate role class")
  }
  add("common.cfg"); add("fragments/network.cfg"); add("fragments/partman.cfg"); add("fragments/apt.cfg")
  count=split(refs,words," ")
  # Selection requirements are explicit opt-ins, not permission to add a
  # hardware driver implicitly while expanding the frozen class plan.
  for(i=1;i<=count;i++) if(words[i]!="") explicit_refs[words[i]]=1
  for(ref in explicit_refs) {
    required_count=split(requires[ref],required_words,",")
    for(i=1;i<=required_count;i++) if(required_words[i]!="" && !(required_words[i] in explicit_refs))
      fail("selected class " ref " requires selected class " required_words[i])
  }
  for(i=1;i<=count;i++) if(words[i]!="") add(words[i])
  # Profile-enabled desktop package policy is an ordinary suite fragment.
  if(profile_ssh=="true" && family=="desktop") add("fragments/ssh.cfg")
  if(snapshots=="timeshift-btrfs") add("fragments/timeshift.cfg")
  else if(snapshots!="none") fail("unregistered snapshot policy")
  add("fragments/finish.cfg")
  rolecount=0
  for(ref in selected) {
    if(ref ~ /^role\//) {
      rolecount++
      if(!(ref in requested)) fail("role closure differs from requested roles: selected=" ref " requested=" roles)
    }
    count=split(conflicts[ref],words,",")
    for(i=1;i<=count;i++) if(words[i] in selected) fail("conflicting selected classes: " ref " and " words[i])
  }
  if(rolecount!=requested_count) fail("selected roles differ from requested roles: selected_count=" rolecount " requested_count=" requested_count " requested=" roles)
  if(family=="desktop" && rolecount!=1) fail("exactly one desktop role is required")
  if(family!="desktop" && family!="server") fail("unsupported role family")
  phases["preseed"]=1; phases["early"]=2; phases["partman"]=3; phases["pre-pkgsel"]=4; phases["late"]=5; phases["firstboot"]=6
  for(i=1;i<=stagecount;i++) if(selected[stageclass[i]]) {
    name=stageid[i]
    if(name=="os.timeshift" && snapshots=="none") continue
    if(name in stages) {
      previous=stages[name]
      if(phase[previous]!=phase[i] || provider[previous]!=provider[i] || after[previous]!=after[i] || before[previous]!=before[i])
        fail("selected classes disagree on shared stage declaration")
      continue
    }
    stages[name]=i
    if(!(phase[i] in phases)) fail("unregistered phase")
  }
  for(name in stages) {
    j=stages[name]; count=split(before[j],words,",")
    for(i=1;i<=count;i++) if(words[i] in stages) {
      k=stages[words[i]]; after[k]=after[k] "," name
    }
  }
  print "format","2"; print "suite",suite; print "family",family; print "architecture",architecture
  print "codex_only_enable",profile_codex_only
  print "codex_enable",(codex_enabled ? "true" : "false")
  # Profile opt-ins and role-derived capabilities are different contracts.
  # Emit each singleton once; consumers use the effective capability keys.
  print "requested_whisper_enable",profile_whisper_enable
  print "requested_llama_enable",profile_llama_enable
  print "whisper_enable",(("desktop.whisper" in stages || "server.whisper" in stages) ? "true" : "false")
  print "llama_enable",(((family=="desktop" && "desktop.devops" in stages) || "server.llama" in stages) ? "true" : "false")
  for(i=1;i<=requested_count;i++) print "role",requested_roles[i]
  for(j=1;j<=classcount;j++) {
    ref=order[j]
    if(ref!="common.cfg" && ref !~ /^fragments\//) print "class",ref
    count=split(packages[ref],words,",")
    for(i=1;i<=count;i++) if(words[i]!="") {
      package=words[i]
      if(package=="timeshift" && snapshots=="none") fail("disabled Timeshift appears in an unconditional class")
      if(!package_seen[package]++) {
        print "package",package
        package_list=package_list (package_list=="" ? "" : " ") package
      }
      print "package-owner",package "|" ref
    }
  }
  emit_answers()
  if(snapshots=="none") print "omission","timeshift|TIMESHIFT_ENABLE=false"
  for(i=1;i<=stagecount;i++) if(selected[stageclass[i]] && stageid[i] in stages)
    print "stage-owner",stageid[i] "|" stageclass[i]
  for(iteration=1;;iteration++) {
    best=""; remaining=0
    for(name in stages) if(!finished[name]) {
      j=stages[name]; remaining++; ready=1; count=split(after[j],words,",")
      for(i=1;i<=count;i++) if(words[i]!="") {
        if(!(words[i] in stages)) fail("missing class stage dependency")
        k=stages[words[i]]
        if(phases[phase[k]]>phases[phase[j]]) fail("phase inversion")
        if(!finished[words[i]]) ready=0
      }
      if(ready && (best=="" || phases[phase[j]]<phases[phase[stages[best]]] || (phase[j]==phase[stages[best]] && name<best))) best=name
    }
    if(!remaining) break
    if(best=="" || iteration>limit) fail("class stage cycle")
    j=stages[best]; identity=phase[j] "|" provider[j]
    if(helper_seen[identity]++) fail("helper selected twice in phase")
    print "stage",best "|" phase[j] "|" provider[j]
    finished[best]=1
  }
}
