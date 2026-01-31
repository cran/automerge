## -----------------------------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## -----------------------------------------------------------------------------
library(automerge)

## -----------------------------------------------------------------------------
# Create two peers with different data
peer1 <- am_create()
peer1[["edited_by"]] <- "peer1"
peer1[["data1"]] <- 100
am_commit(peer1, "Peer1 changes")

peer2 <- am_create()
peer2[["edited_by"]] <- "peer2"
peer2[["data2"]] <- 200
am_commit(peer2, "Peer2 changes")

# Automatic bidirectional sync (documents modified in place)
rounds <- am_sync(peer1, peer2)

rounds

# Both documents now have all data
peer1[["data1"]]
peer1[["data2"]]
peer2[["data1"]]
peer2[["data2"]]

## -----------------------------------------------------------------------------
# Create source document
source <- am_create()
source[["version"]] <- "2.0"
source[["features"]] <- list("auth", "api")
am_commit(source)

# Create target document
target <- am_create()
target[["version"]] <- "1.0"
target[["development"]] <- TRUE
am_commit(target)

# Pull changes from source to target
am_merge(target, source)

# Target now has source's changes
target[["version"]]

# Source is unchanged
names(source)

## -----------------------------------------------------------------------------
# Create two peers
peer3 <- am_create()
peer3[["source"]] <- "peer3"
am_commit(peer3)

peer4 <- am_create()
peer4[["source"]] <- "peer4"
am_commit(peer4)

# Each peer maintains its own sync state
sync3 <- am_sync_state_new()
sync4 <- am_sync_state_new()

# Exchange messages until converged
round <- 0
repeat {
  round <- round + 1

  # Peer 3 generates message
  msg3 <- am_sync_encode(peer3, sync3)
  if (is.null(msg3)) {
    break
  } # No more messages

  # Peer 4 receives and processes
  am_sync_decode(peer4, sync4, msg3)

  # Peer 4 generates response
  msg4 <- am_sync_encode(peer4, sync4)
  if (is.null(msg4)) {
    break
  } # No more messages

  # Peer 3 receives and processes
  am_sync_decode(peer3, sync3, msg4)

  if (round > 100) {
    warning("Sync did not converge in 100 rounds")
    break
  }
}

round
peer3[["source"]]
peer4[["source"]]

## -----------------------------------------------------------------------------
# Create base document that will be shared
base_doc <- am_create()
base_doc[["v1"]] <- "first"
am_commit(base_doc, "Version 1")

# Fork to create two peers with shared history
peer_a <- am_fork(base_doc)
peer_b <- am_fork(base_doc)

# Remember the fork point
fork_heads <- am_get_heads(peer_a)

# Peer A makes changes
peer_a[["v2"]] <- "second"
am_commit(peer_a, "Version 2")

peer_a[["v3"]] <- "third"
am_commit(peer_a, "Version 3")

# Export changes since fork point
changes <- am_get_changes(peer_a, fork_heads)

length(changes)

# Peer B applies the changes
am_apply_changes(peer_b, changes)

# Verify both peers are in sync
peer_b[["v2"]]
peer_b[["v3"]]

## -----------------------------------------------------------------------------
# Save individual changes to files
temp_dir <- tempdir()
for (i in seq_along(changes)) {
  change_file <- file.path(temp_dir, sprintf("change_%03d.bin", i))
  writeBin(changes[[i]], change_file)
}

# Later: load and apply changes
loaded_changes <- list()
for (i in seq_along(changes)) {
  change_file <- file.path(temp_dir, sprintf("change_%03d.bin", i))
  loaded_changes[[i]] <- readBin(change_file, "raw", file.size(change_file))
}

# Apply loaded changes to a peer
peer_c <- am_fork(base_doc)
am_apply_changes(peer_c, loaded_changes)

# Verify
peer_c[["v3"]]

## -----------------------------------------------------------------------------
# Create document and make changes
doc_main <- am_create()
doc_main[["version"]] <- "1.0"
am_commit(doc_main, "Initial version")

# Get heads (fingerprint of current state)
heads_v1 <- am_get_heads(doc_main)
length(heads_v1)

# Make more changes
doc_main[["version"]] <- "2.0"
doc_main[["feature"]] <- "new"
am_commit(doc_main, "Version 2")

heads_v2 <- am_get_heads(doc_main)
identical(heads_v1, heads_v2)

## -----------------------------------------------------------------------------
# Get full change history
history <- am_get_history(doc_main)
length(history)

# History includes all commits ever made
# Each entry contains metadata about a commit

# Get changes between two points in history
changes_since_v1 <- am_get_changes(doc_main, heads_v1)
str(changes_since_v1)

## -----------------------------------------------------------------------------
# Server document that accumulates changes
server <- am_create()
server[["users"]] <- 0L
am_commit(server, "Initialize")

# Client syncs and remembers server state
client <- am_fork(server)
last_sync_heads <- am_get_heads(server)

# Client makes local changes
client[["users"]] <- 1L
client[["local_cache"]] <- TRUE
am_commit(client, "Client updates")

# Server receives changes from other clients
server[["users"]] <- 5L
server[["server_config"]] <- "production"
am_commit(server, "Server updates")

# Client pulls only new server changes since last sync
new_changes <- am_get_changes(server, last_sync_heads)
length(new_changes)

am_apply_changes(client, new_changes)

# Update sync point
last_sync_heads <- am_get_heads(server)

# Client now has server's changes
client[["server_config"]]

# Server can also pull client's changes
client_changes <- am_get_changes(client, am_get_heads(server))
am_apply_changes(server, client_changes)

server[["local_cache"]]

## -----------------------------------------------------------------------------
# Create two peers that will diverge
peer_x <- am_create()
peer_x[["id"]] <- "x"
am_commit(peer_x)

peer_y <- am_fork(peer_x)

# Remember common state
common_heads <- am_get_heads(peer_x)

# Both make different changes
peer_x[["data_x"]] <- "from X"
am_commit(peer_x, "X's change")

peer_y[["data_y"]] <- "from Y"
am_commit(peer_y, "Y's change")

# Check if they've diverged
x_heads <- am_get_heads(peer_x)
y_heads <- am_get_heads(peer_y)

identical(x_heads, y_heads)

# Get each peer's changes since common state
x_changes <- am_get_changes(peer_x, common_heads)
y_changes <- am_get_changes(peer_y, common_heads)

str(x_changes)
str(y_changes)

# Sync to merge divergent histories
rounds <- am_sync(peer_x, peer_y)
rounds

# After sync, heads are identical again
identical(am_get_heads(peer_x), am_get_heads(peer_y))

## -----------------------------------------------------------------------------
# Create shared starting point
base <- am_create()
base[["counter"]] <- am_counter(0)
base[["status"]] <- "draft"
am_commit(base)

# Fork to two editors
editor1 <- am_fork(base)
editor2 <- am_fork(base)

# Concurrent edits
# Editor 1: increment counter, change status
am_counter_increment(editor1, AM_ROOT, "counter", 5)
editor1[["status"]] <- "review"
am_commit(editor1, "Editor 1 changes")

# Editor 2: increment counter differently, change status differently
am_counter_increment(editor2, AM_ROOT, "counter", 3)
editor2[["status"]] <- "published"
am_commit(editor2, "Editor 2 changes")

# Sync editors
rounds <- am_sync(editor1, editor2)

# Counter: Both increments sum (CRDT)
editor1[["counter"]]

# Status: Deterministic conflict resolution (one value wins)
editor1[["status"]]

## -----------------------------------------------------------------------------
# Strategy A: Frequent sync (lower latency, more overhead)
doc_frequent <- am_create()
peer_frequent <- am_create()

sync_count_frequent <- 0
for (i in 1:10) {
  doc_frequent[[paste0("k", i)]] <- i
  am_commit(doc_frequent, paste("Change", i))

  rounds <- am_sync(doc_frequent, peer_frequent)
  sync_count_frequent <- sync_count_frequent + 1
}

# 10 separate commits, 10 sync operations
sync_count_frequent

# Strategy B: Batched commits (higher latency, less overhead)
doc_batched <- am_create()
peer_batched <- am_create()

# Batch all changes into one commit
for (i in 1:10) {
  doc_batched[[paste0("k", i)]] <- i
}
am_commit(doc_batched, "Batch of 10 changes")

rounds <- am_sync(doc_batched, peer_batched)

# 1 commit, 1 sync operation
rounds

# Compare document sizes
length(am_save(doc_frequent))
length(am_save(doc_batched))

## -----------------------------------------------------------------------------
# Batch related changes, sync periodically
doc_hybrid <- am_create()

# User fills out a form (batch these)
doc_hybrid[["name"]] <- "Alice"
doc_hybrid[["email"]] <- "alice@example.com"
doc_hybrid[["preferences"]] <- list("theme" = "dark")
am_commit(doc_hybrid, "Update user profile")

# Sync after logical unit of work
# result <- sync_with_server(doc_hybrid)

# Later: another logical unit
doc_hybrid[["last_login"]] <- Sys.time()
am_commit(doc_hybrid, "Record login")

# Sync again
# result <- sync_with_server(doc_hybrid)

## -----------------------------------------------------------------------------
# Without reusing sync state (inefficient)
doc_no_reuse <- am_create()
doc_no_reuse[["v1"]] <- 1
am_commit(doc_no_reuse)

peer_no_reuse <- am_create()

# First sync
rounds1 <- am_sync(doc_no_reuse, peer_no_reuse)
rounds1

# Add more changes
doc_no_reuse[["v2"]] <- 2
am_commit(doc_no_reuse)

# Second sync (creates new sync state, may resend some data)
rounds2 <- am_sync(doc_no_reuse, peer_no_reuse)
rounds2

# With reusing sync state (efficient)
doc_reuse <- am_create()
doc_reuse[["v1"]] <- 1
am_commit(doc_reuse)

peer_reuse <- am_create()
sync_state_local <- am_sync_state_new()
sync_state_peer <- am_sync_state_new()

# Manual sync with persistent state
msg1 <- am_sync_encode(doc_reuse, sync_state_local)
am_sync_decode(peer_reuse, sync_state_peer, msg1)
msg2 <- am_sync_encode(peer_reuse, sync_state_peer)

if (!is.null(msg2)) {
  am_sync_decode(doc_reuse, sync_state_local, msg2)
}

# Add more changes
doc_reuse[["v2"]] <- 2
am_commit(doc_reuse)

# Second sync reuses state (only sends new changes)
msg3 <- am_sync_encode(doc_reuse, sync_state_local)
am_sync_decode(peer_reuse, sync_state_peer, msg3)

# Sync state remembers what was already exchanged

## -----------------------------------------------------------------------------
# Compare efficiency of different approaches
measure_sync <- function(n_changes, batch_size) {
  doc <- am_create()
  peer <- am_create()

  changes_made <- 0
  syncs_performed <- 0

  for (i in seq_len(n_changes)) {
    doc[[paste0("k", i)]] <- i
    changes_made <- changes_made + 1

    # Commit every batch_size changes
    if (changes_made %% batch_size == 0) {
      am_commit(doc, sprintf("Batch at %d", changes_made))
      rounds <- am_sync(doc, peer)
      syncs_performed <- syncs_performed + 1
    }
  }

  # Final commit if needed
  if (changes_made %% batch_size != 0) {
    am_commit(doc, "Final batch")
    rounds <- am_sync(doc, peer)
    syncs_performed <- syncs_performed + 1
  }

  list(
    changes = changes_made,
    syncs = syncs_performed,
    size = length(am_save(doc))
  )
}

# No batching: commit and sync after every change
result_no_batch <- measure_sync(20, 1)

# Medium batching: commit every 5 changes
result_medium <- measure_sync(20, 5)

# Full batching: single commit at end
result_full <- measure_sync(20, 20)

# Compare results
result_no_batch$syncs
result_medium$syncs
result_full$syncs

# Document sizes
result_no_batch$size
result_medium$size
result_full$size

