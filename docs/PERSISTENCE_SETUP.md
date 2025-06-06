# Circuit Breaker Persistence Setup Guide

This guide details how to set up persistence stores for H2O's circuit breaker functionality, including database schemas, adapters, and best practices for production deployments.

## Table of Contents

- [Overview](#overview)
- [Database Persistence](#database-persistence)
- [Redis Persistence](#redis-persistence)
- [File-Based Persistence](#file-based-persistence)
- [Custom Persistence Adapters](#custom-persistence-adapters)
- [Migration Strategies](#migration-strategies)
- [Performance Considerations](#performance-considerations)
- [Monitoring and Maintenance](#monitoring-and-maintenance)

## Overview

H2O's circuit breaker can persist state across application restarts using various storage backends. This ensures that circuit breaker state is maintained even during deployments or service restarts.

### Available Persistence Options

1. **Database Persistence** - PostgreSQL, MySQL, SQLite
2. **Redis Persistence** - Single instance or cluster
3. **File-Based Persistence** - Local JSON files
4. **In-Memory Persistence** - Testing only
5. **Custom Adapters** - Your own implementation

## Database Persistence

### PostgreSQL Setup

#### 1. Create Database Schema

```sql
-- Circuit breaker states table
CREATE TABLE circuit_breaker_states (
    id SERIAL PRIMARY KEY,
    service_name VARCHAR(255) UNIQUE NOT NULL,
    state VARCHAR(20) NOT NULL CHECK (state IN ('closed', 'open', 'half_open')),
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    failure_count INTEGER NOT NULL DEFAULT 0,
    last_failure_time TIMESTAMP NULL,
    last_success_time TIMESTAMP NULL,
    success_count INTEGER NOT NULL DEFAULT 0,
    timeout_count INTEGER NOT NULL DEFAULT 0,
    total_requests INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_circuit_breaker_service_name ON circuit_breaker_states(service_name);
CREATE INDEX idx_circuit_breaker_state ON circuit_breaker_states(state);
CREATE INDEX idx_circuit_breaker_updated_at ON circuit_breaker_states(updated_at);

-- Optional: Historical data table for analytics
CREATE TABLE circuit_breaker_history (
    id BIGSERIAL PRIMARY KEY,
    service_name VARCHAR(255) NOT NULL,
    state_change VARCHAR(50) NOT NULL, -- 'closed_to_open', 'open_to_half_open', etc.
    old_state VARCHAR(20) NOT NULL,
    new_state VARCHAR(20) NOT NULL,
    consecutive_failures INTEGER NOT NULL,
    failure_count INTEGER NOT NULL,
    total_requests INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_circuit_breaker_history_service ON circuit_breaker_history(service_name);
CREATE INDEX idx_circuit_breaker_history_created_at ON circuit_breaker_history(created_at);
```

#### 2. PostgreSQL Persistence Adapter

```crystal
require "pg"
require "h2o"

class PostgreSQLPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@db : DB::Database, @track_history : Bool = false)
    ensure_schema_exists
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    @db.query_one?(
      "SELECT state, consecutive_failures, failure_count, last_failure_time, 
              last_success_time, success_count, timeout_count, total_requests 
       FROM circuit_breaker_states WHERE service_name = $1",
      name
    ) do |rs|
      H2O::CircuitBreaker::CircuitBreakerState.new(
        consecutive_failures: rs.read(Int32),
        failure_count: rs.read(Int32),
        last_failure_time: rs.read(Time?),
        last_success_time: rs.read(Time?),
        state: H2O::CircuitBreaker::State.parse(rs.read(String)),
        success_count: rs.read(Int32),
        timeout_count: rs.read(Int32),
        total_requests: rs.read(Int32)
      )
    end
  rescue ex : Exception
    Log.error { "Failed to load circuit breaker state for #{name}: #{ex.message}" }
    nil
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    # Get current state for history tracking
    current_state = load_current_state_only(name) if @track_history

    # Save new state
    @db.exec(
      "INSERT INTO circuit_breaker_states 
       (service_name, state, consecutive_failures, failure_count, last_failure_time,
        last_success_time, success_count, timeout_count, total_requests, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
       ON CONFLICT (service_name) DO UPDATE SET
         state = EXCLUDED.state,
         consecutive_failures = EXCLUDED.consecutive_failures,
         failure_count = EXCLUDED.failure_count,
         last_failure_time = EXCLUDED.last_failure_time,
         last_success_time = EXCLUDED.last_success_time,
         success_count = EXCLUDED.success_count,
         timeout_count = EXCLUDED.timeout_count,
         total_requests = EXCLUDED.total_requests,
         updated_at = NOW()",
      name, state.state.to_s, state.consecutive_failures, state.failure_count,
      state.last_failure_time, state.last_success_time, state.success_count,
      state.timeout_count, state.total_requests
    )

    # Track state changes in history
    if @track_history && current_state && current_state != state.state.to_s
      track_state_change(name, current_state, state.state.to_s, state)
    end

  rescue ex : Exception
    Log.error { "Failed to save circuit breaker state for #{name}: #{ex.message}" }
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    # Statistics are included in state loading
    nil
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
    # Statistics are saved with state
  end

  # Additional helper methods
  def cleanup_old_records(days : Int32 = 30) : Nil
    @db.exec(
      "DELETE FROM circuit_breaker_history WHERE created_at < NOW() - INTERVAL '#{days} days'"
    )
  rescue ex : Exception
    Log.error { "Failed to cleanup old circuit breaker history: #{ex.message}" }
  end

  def get_service_statistics(service_name : String, since : Time) : Hash(String, Int32)
    result = Hash(String, Int32).new(0)
    
    @db.query_all(
      "SELECT state_change, COUNT(*) 
       FROM circuit_breaker_history 
       WHERE service_name = $1 AND created_at >= $2 
       GROUP BY state_change",
      service_name, since
    ) do |rs|
      result[rs.read(String)] = rs.read(Int32)
    end
    
    result
  rescue ex : Exception
    Log.error { "Failed to get service statistics: #{ex.message}" }
    result
  end

  private def ensure_schema_exists : Nil
    @db.exec <<-SQL
      CREATE TABLE IF NOT EXISTS circuit_breaker_states (
        id SERIAL PRIMARY KEY,
        service_name VARCHAR(255) UNIQUE NOT NULL,
        state VARCHAR(20) NOT NULL,
        consecutive_failures INTEGER NOT NULL DEFAULT 0,
        failure_count INTEGER NOT NULL DEFAULT 0,
        last_failure_time TIMESTAMP NULL,
        last_success_time TIMESTAMP NULL,
        success_count INTEGER NOT NULL DEFAULT 0,
        timeout_count INTEGER NOT NULL DEFAULT 0,
        total_requests INTEGER NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMP NOT NULL DEFAULT NOW()
      );
      
      CREATE INDEX IF NOT EXISTS idx_circuit_breaker_service_name 
      ON circuit_breaker_states(service_name);
    SQL

    if @track_history
      @db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS circuit_breaker_history (
          id BIGSERIAL PRIMARY KEY,
          service_name VARCHAR(255) NOT NULL,
          state_change VARCHAR(50) NOT NULL,
          old_state VARCHAR(20) NOT NULL,
          new_state VARCHAR(20) NOT NULL,
          consecutive_failures INTEGER NOT NULL,
          failure_count INTEGER NOT NULL,
          total_requests INTEGER NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
        
        CREATE INDEX IF NOT EXISTS idx_circuit_breaker_history_service 
        ON circuit_breaker_history(service_name);
        
        CREATE INDEX IF NOT EXISTS idx_circuit_breaker_history_created_at 
        ON circuit_breaker_history(created_at);
      SQL
    end
  end

  private def load_current_state_only(name : String) : String?
    @db.query_one?("SELECT state FROM circuit_breaker_states WHERE service_name = $1", name, &.read(String))
  end

  private def track_state_change(name : String, old_state : String, new_state : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    state_change = "#{old_state}_to_#{new_state}"
    
    @db.exec(
      "INSERT INTO circuit_breaker_history 
       (service_name, state_change, old_state, new_state, consecutive_failures, 
        failure_count, total_requests)
       VALUES ($1, $2, $3, $4, $5, $6, $7)",
      name, state_change, old_state, new_state, state.consecutive_failures,
      state.failure_count, state.total_requests
    )
  end
end

# Usage
db = DB.open(ENV["DATABASE_URL"])
persistence = PostgreSQLPersistence.new(db, track_history: true)

# Cleanup old history records daily
spawn do
  loop do
    sleep 24.hours
    persistence.cleanup_old_records(30)
  end
end
```

### MySQL Setup

#### 1. MySQL Schema

```sql
-- Circuit breaker states table for MySQL
CREATE TABLE circuit_breaker_states (
    id INT AUTO_INCREMENT PRIMARY KEY,
    service_name VARCHAR(255) UNIQUE NOT NULL,
    state ENUM('closed', 'open', 'half_open') NOT NULL,
    consecutive_failures INT NOT NULL DEFAULT 0,
    failure_count INT NOT NULL DEFAULT 0,
    last_failure_time TIMESTAMP NULL,
    last_success_time TIMESTAMP NULL,
    success_count INT NOT NULL DEFAULT 0,
    timeout_count INT NOT NULL DEFAULT 0,
    total_requests INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX idx_circuit_breaker_service_name ON circuit_breaker_states(service_name);
CREATE INDEX idx_circuit_breaker_state ON circuit_breaker_states(state);
CREATE INDEX idx_circuit_breaker_updated_at ON circuit_breaker_states(updated_at);
```

#### 2. MySQL Persistence Adapter

```crystal
require "mysql"

class MySQLPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@db : DB::Database)
    ensure_schema_exists
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    @db.query_one?(
      "SELECT state, consecutive_failures, failure_count, last_failure_time, 
              last_success_time, success_count, timeout_count, total_requests 
       FROM circuit_breaker_states WHERE service_name = ?",
      name
    ) do |rs|
      H2O::CircuitBreaker::CircuitBreakerState.new(
        consecutive_failures: rs.read(Int32),
        failure_count: rs.read(Int32),
        last_failure_time: rs.read(Time?),
        last_success_time: rs.read(Time?),
        state: H2O::CircuitBreaker::State.parse(rs.read(String)),
        success_count: rs.read(Int32),
        timeout_count: rs.read(Int32),
        total_requests: rs.read(Int32)
      )
    end
  rescue ex : Exception
    Log.error { "MySQL load error for #{name}: #{ex.message}" }
    nil
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    @db.exec(
      "INSERT INTO circuit_breaker_states 
       (service_name, state, consecutive_failures, failure_count, last_failure_time,
        last_success_time, success_count, timeout_count, total_requests)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         state = VALUES(state),
         consecutive_failures = VALUES(consecutive_failures),
         failure_count = VALUES(failure_count),
         last_failure_time = VALUES(last_failure_time),
         last_success_time = VALUES(last_success_time),
         success_count = VALUES(success_count),
         timeout_count = VALUES(timeout_count),
         total_requests = VALUES(total_requests)",
      name, state.state.to_s, state.consecutive_failures, state.failure_count,
      state.last_failure_time, state.last_success_time, state.success_count,
      state.timeout_count, state.total_requests
    )
  rescue ex : Exception
    Log.error { "MySQL save error for #{name}: #{ex.message}" }
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    nil
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
  end

  private def ensure_schema_exists : Nil
    @db.exec <<-SQL
      CREATE TABLE IF NOT EXISTS circuit_breaker_states (
        id INT AUTO_INCREMENT PRIMARY KEY,
        service_name VARCHAR(255) UNIQUE NOT NULL,
        state ENUM('closed', 'open', 'half_open') NOT NULL,
        consecutive_failures INT NOT NULL DEFAULT 0,
        failure_count INT NOT NULL DEFAULT 0,
        last_failure_time TIMESTAMP NULL,
        last_success_time TIMESTAMP NULL,
        success_count INT NOT NULL DEFAULT 0,
        timeout_count INT NOT NULL DEFAULT 0,
        total_requests INT NOT NULL DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      )
    SQL
  end
end
```

## Redis Persistence

### Single Redis Instance

```crystal
require "redis"

class RedisPersistence < H2O::CircuitBreaker::PersistenceAdapter
  TTL = 86400 # 24 hours

  def initialize(@redis : Redis, @prefix : String = "circuit_breaker")
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    key = "#{@prefix}:state:#{name}"
    data = @redis.get(key)
    return nil unless data
    
    H2O::CircuitBreaker::CircuitBreakerState.from_json(data)
  rescue ex : Exception
    Log.error { "Redis load error for #{name}: #{ex.message}" }
    nil
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    key = "#{@prefix}:state:#{name}"
    @redis.setex(key, TTL, state.to_json)
    
    # Also store last update timestamp
    @redis.setex("#{@prefix}:updated:#{name}", TTL, Time.utc.to_unix.to_s)
  rescue ex : Exception
    Log.error { "Redis save error for #{name}: #{ex.message}" }
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    nil # Included in state
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
    # Included in state
  end

  # Additional Redis-specific methods
  def get_all_services : Array(String)
    pattern = "#{@prefix}:state:*"
    keys = @redis.keys(pattern)
    keys.map { |key| key.gsub("#{@prefix}:state:", "") }
  rescue ex : Exception
    Log.error { "Failed to get all services: #{ex.message}" }
    [] of String
  end

  def cleanup_expired_keys : Int32
    pattern = "#{@prefix}:*"
    keys = @redis.keys(pattern)
    expired_count = 0
    
    keys.each do |key|
      ttl = @redis.ttl(key)
      if ttl == -1 # No expiration set
        @redis.expire(key, TTL)
      elsif ttl == -2 # Key doesn't exist
        expired_count += 1
      end
    end
    
    expired_count
  rescue ex : Exception
    Log.error { "Failed to cleanup expired keys: #{ex.message}" }
    0
  end
end

# Usage
redis = Redis.new(host: ENV["REDIS_HOST"]?, port: ENV["REDIS_PORT"]?.try(&.to_i) || 6379)
persistence = RedisPersistence.new(redis)
```

### Redis Cluster

```crystal
class RedisClusterPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@redis_nodes : Array(Redis), @replication_factor : Int32 = 2)
    @hash_ring = ConsistentHashRing.new(@redis_nodes)
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    nodes = get_nodes_for_key(name)
    
    # Try to load from multiple nodes for redundancy
    nodes.each do |redis|
      begin
        key = "circuit_breaker:state:#{name}"
        data = redis.get(key)
        if data
          return H2O::CircuitBreaker::CircuitBreakerState.from_json(data)
        end
      rescue ex : Exception
        Log.warn { "Failed to load from Redis node: #{ex.message}" }
        next
      end
    end
    
    nil
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    nodes = get_nodes_for_key(name)
    key = "circuit_breaker:state:#{name}"
    data = state.to_json
    
    # Save to multiple nodes for redundancy
    nodes.each do |redis|
      spawn do
        begin
          redis.setex(key, 86400, data)
        rescue ex : Exception
          Log.error { "Failed to save to Redis node: #{ex.message}" }
        end
      end
    end
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    nil
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
  end

  private def get_nodes_for_key(key : String) : Array(Redis)
    primary_node = @hash_ring.get_node(key)
    nodes = [primary_node]
    
    # Add additional nodes for replication
    (@replication_factor - 1).times do
      node = @hash_ring.get_next_node(key, nodes.last)
      nodes << node if node != primary_node
    end
    
    nodes.uniq
  end
end
```

## File-Based Persistence

### Enhanced Local File Persistence

```crystal
class EnhancedLocalFilePersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@storage_path : String = "./.h2o_circuit_breaker", @backup_count : Int32 = 3)
    setup_storage_directory
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    state_file = File.join(@storage_path, "#{name}_state.json")
    
    return nil unless File.exists?(state_file)
    
    content = File.read(state_file)
    H2O::CircuitBreaker::CircuitBreakerState.from_json(content)
  rescue ex : Exception
    Log.warn { "Failed to load state for #{name}: #{ex.message}" }
    try_load_from_backup(name)
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    state_file = File.join(@storage_path, "#{name}_state.json")
    temp_file = "#{state_file}.tmp"
    
    # Create backup before saving
    create_backup(name) if File.exists?(state_file)
    
    # Write to temporary file first
    File.write(temp_file, state.to_json)
    
    # Atomic move
    File.rename(temp_file, state_file)
    
    # Save metadata
    save_metadata(name, state)
  rescue ex : Exception
    Log.error { "Failed to save state for #{name}: #{ex.message}" }
    File.delete(temp_file) if File.exists?(temp_file)
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    nil
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
  end

  # Maintenance methods
  def cleanup_old_backups : Nil
    Dir.glob(File.join(@storage_path, "*_state.json.backup.*")).each do |backup_file|
      parts = File.basename(backup_file).split(".")
      if parts.size >= 4
        timestamp = parts[-1]
        if timestamp.to_i? && Time.unix(timestamp.to_i) < (Time.utc - 7.days)
          File.delete(backup_file)
        end
      end
    end
  rescue ex : Exception
    Log.error { "Failed to cleanup old backups: #{ex.message}" }
  end

  def get_storage_info : Hash(String, Int64)
    info = Hash(String, Int64).new
    
    Dir.glob(File.join(@storage_path, "*.json")).each do |file|
      info[File.basename(file)] = File.size(file)
    end
    
    info
  end

  private def setup_storage_directory : Nil
    Dir.mkdir_p(@storage_path) unless Dir.exists?(@storage_path)
    
    # Create .gitignore to avoid committing circuit breaker data
    gitignore_path = File.join(@storage_path, ".gitignore")
    unless File.exists?(gitignore_path)
      File.write(gitignore_path, "*\n!.gitignore\n")
    end
  end

  private def create_backup(name : String) : Nil
    state_file = File.join(@storage_path, "#{name}_state.json")
    backup_file = "#{state_file}.backup.#{Time.utc.to_unix}"
    
    File.copy(state_file, backup_file)
    
    # Cleanup old backups for this service
    cleanup_service_backups(name)
  end

  private def cleanup_service_backups(name : String) : Nil
    pattern = File.join(@storage_path, "#{name}_state.json.backup.*")
    backups = Dir.glob(pattern)
    
    if backups.size > @backup_count
      # Keep only the most recent backups
      sorted_backups = backups.sort_by do |file|
        timestamp = File.basename(file).split(".").last
        timestamp.to_i? || 0
      end
      
      old_backups = sorted_backups[0..-(1 + @backup_count)]
      old_backups.each { |file| File.delete(file) }
    end
  end

  private def try_load_from_backup(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    pattern = File.join(@storage_path, "#{name}_state.json.backup.*")
    backups = Dir.glob(pattern).sort.reverse
    
    backups.each do |backup_file|
      begin
        content = File.read(backup_file)
        Log.info { "Loaded circuit breaker state from backup: #{backup_file}" }
        return H2O::CircuitBreaker::CircuitBreakerState.from_json(content)
      rescue ex : Exception
        Log.warn { "Failed to load from backup #{backup_file}: #{ex.message}" }
        next
      end
    end
    
    nil
  end

  private def save_metadata(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    metadata_file = File.join(@storage_path, "#{name}_metadata.json")
    metadata = {
      service_name: name,
      last_updated: Time.utc.to_rfc3339,
      state: state.state.to_s,
      total_requests: state.total_requests,
      failure_rate: calculate_failure_rate(state)
    }
    
    File.write(metadata_file, metadata.to_json)
  end

  private def calculate_failure_rate(state : H2O::CircuitBreaker::CircuitBreakerState) : Float64
    return 0.0 if state.total_requests == 0
    (state.failure_count.to_f / state.total_requests * 100).round(2)
  end
end
```

## Custom Persistence Adapters

### Multi-Backend Persistence

```crystal
class MultiBeckendPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@primary : H2O::CircuitBreaker::PersistenceAdapter, 
                 @secondary : H2O::CircuitBreaker::PersistenceAdapter,
                 @prefer_primary : Bool = true)
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    if @prefer_primary
      @primary.load_state(name) || @secondary.load_state(name)
    else
      @secondary.load_state(name) || @primary.load_state(name)
    end
  rescue ex : Exception
    Log.warn { "Primary persistence failed, trying secondary: #{ex.message}" }
    @secondary.load_state(name)
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    # Save to both backends asynchronously
    primary_fiber = spawn { @primary.save_state(name, state) }
    secondary_fiber = spawn { @secondary.save_state(name, state) }
    
    # Wait for both to complete
    primary_fiber.join
    secondary_fiber.join
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    @primary.load_statistics(name) || @secondary.load_statistics(name)
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
    spawn { @primary.save_statistics(name, stats) }
    spawn { @secondary.save_statistics(name, stats) }
  end
end

# Usage
primary = PostgreSQLPersistence.new(Database.connection)
secondary = RedisPersistence.new(Redis.connection)
persistence = MultiBeckendPersistence.new(primary, secondary)
```

### Async Write Persistence

```crystal
class AsyncWritePersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@underlying : H2O::CircuitBreaker::PersistenceAdapter, @queue_size : Int32 = 1000)
    @write_queue = Channel({String, String, H2O::CircuitBreaker::CircuitBreakerState}).new(@queue_size)
    @stats_queue = Channel({String, String, H2O::CircuitBreaker::Statistics}).new(@queue_size)
    
    start_background_writer
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    @underlying.load_state(name)
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    # Async save - don't block
    @write_queue.try_send({"state", name, state})
  rescue Channel::ClosedError
    Log.error { "Write queue is closed, falling back to synchronous save" }
    @underlying.save_state(name, state)
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    @underlying.load_statistics(name)
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
    @stats_queue.try_send({"stats", name, stats})
  rescue Channel::ClosedError
    @underlying.save_statistics(name, stats)
  end

  def close : Nil
    @write_queue.close
    @stats_queue.close
  end

  private def start_background_writer : Nil
    spawn(name: "circuit_breaker_async_writer") do
      loop do
        select
        when message = @write_queue.receive
          type, name, data = message
          case type
          when "state"
            @underlying.save_state(name, data.as(H2O::CircuitBreaker::CircuitBreakerState))
          end
        when message = @stats_queue.receive
          type, name, data = message
          @underlying.save_statistics(name, data.as(H2O::CircuitBreaker::Statistics))
        end
      rescue Channel::ClosedError
        break
      rescue ex : Exception
        Log.error { "Background writer error: #{ex.message}" }
      end
    end
  end
end
```

## Migration Strategies

### Zero-Downtime Migration

```crystal
class MigrationPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@old_persistence : H2O::CircuitBreaker::PersistenceAdapter,
                 @new_persistence : H2O::CircuitBreaker::PersistenceAdapter,
                 @migration_phase : String = "read_old_write_both")
    # Phases: read_old_write_both -> read_both_write_both -> read_new_write_both -> read_new_write_new
  end

  def load_state(name : String) : H2O::CircuitBreaker::CircuitBreakerState?
    case @migration_phase
    when "read_old_write_both"
      @old_persistence.load_state(name)
    when "read_both_write_both"
      @new_persistence.load_state(name) || @old_persistence.load_state(name)
    when "read_new_write_both", "read_new_write_new"
      @new_persistence.load_state(name)
    else
      @old_persistence.load_state(name)
    end
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    case @migration_phase
    when "read_old_write_both", "read_both_write_both", "read_new_write_both"
      # Write to both during migration
      spawn { @old_persistence.save_state(name, state) }
      spawn { @new_persistence.save_state(name, state) }
    when "read_new_write_new"
      @new_persistence.save_state(name, state)
    else
      @old_persistence.save_state(name, state)
    end
  end

  def load_statistics(name : String) : H2O::CircuitBreaker::Statistics?
    case @migration_phase
    when "read_old_write_both"
      @old_persistence.load_statistics(name)
    when "read_both_write_both"
      @new_persistence.load_statistics(name) || @old_persistence.load_statistics(name)
    when "read_new_write_both", "read_new_write_new"
      @new_persistence.load_statistics(name)
    else
      @old_persistence.load_statistics(name)
    end
  end

  def save_statistics(name : String, stats : H2O::CircuitBreaker::Statistics) : Nil
    case @migration_phase
    when "read_old_write_both", "read_both_write_both", "read_new_write_both"
      spawn { @old_persistence.save_statistics(name, stats) }
      spawn { @new_persistence.save_statistics(name, stats) }
    when "read_new_write_new"
      @new_persistence.save_statistics(name, stats)
    else
      @old_persistence.save_statistics(name, stats)
    end
  end

  def advance_migration_phase : Nil
    case @migration_phase
    when "read_old_write_both"
      @migration_phase = "read_both_write_both"
    when "read_both_write_both"
      @migration_phase = "read_new_write_both"
    when "read_new_write_both"
      @migration_phase = "read_new_write_new"
    end
    
    Log.info { "Advanced migration phase to: #{@migration_phase}" }
  end
end
```

## Performance Considerations

### Optimizing Database Performance

```sql
-- PostgreSQL performance optimizations
-- 1. Proper indexing
CREATE INDEX CONCURRENTLY idx_circuit_breaker_service_state 
ON circuit_breaker_states(service_name, state);

-- 2. Partial indexes for active services
CREATE INDEX CONCURRENTLY idx_circuit_breaker_active 
ON circuit_breaker_states(service_name) 
WHERE updated_at > NOW() - INTERVAL '1 hour';

-- 3. Connection pooling in application
-- Use pgbouncer or similar for connection pooling

-- 4. Partitioning for history table (if using)
CREATE TABLE circuit_breaker_history_y2024m01 
PARTITION OF circuit_breaker_history 
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

### Redis Performance Optimization

```crystal
class OptimizedRedisPersistence < H2O::CircuitBreaker::PersistenceAdapter
  def initialize(@redis : Redis, @pipeline_size : Int32 = 10)
    @write_buffer = [] of {String, String}
    @buffer_mutex = Mutex.new
    
    start_batch_writer
  end

  def save_state(name : String, state : H2O::CircuitBreaker::CircuitBreakerState) : Nil
    @buffer_mutex.synchronize do
      @write_buffer << {"#{@prefix}:state:#{name}", state.to_json}
      
      if @write_buffer.size >= @pipeline_size
        flush_buffer
      end
    end
  end

  private def flush_buffer : Nil
    return if @write_buffer.empty?
    
    @redis.pipelined do |pipeline|
      @write_buffer.each do |key, value|
        pipeline.setex(key, 86400, value)
      end
    end
    
    @write_buffer.clear
  end

  private def start_batch_writer : Nil
    spawn do
      loop do
        sleep 1.seconds
        @buffer_mutex.synchronize { flush_buffer }
      end
    end
  end
end
```

## Monitoring and Maintenance

### Persistence Health Monitoring

```crystal
class PersistenceHealthMonitor
  def initialize(@persistence : H2O::CircuitBreaker::PersistenceAdapter, @service_name : String)
    @metrics = MetricsClient.new
    start_monitoring
  end

  private def start_monitoring : Nil
    spawn do
      loop do
        sleep 30.seconds
        check_persistence_health
      end
    end
  end

  private def check_persistence_health : Nil
    start_time = Time.monotonic
    
    begin
      # Test write
      test_state = H2O::CircuitBreaker::CircuitBreakerState.new(
        state: H2O::CircuitBreaker::State::Closed,
        total_requests: 1
      )
      @persistence.save_state("health_check", test_state)
      
      # Test read
      loaded_state = @persistence.load_state("health_check")
      
      duration = Time.monotonic - start_time
      
      if loaded_state
        @metrics.gauge("circuit_breaker.persistence.health", 1, {service: @service_name})
        @metrics.histogram("circuit_breaker.persistence.latency", duration.total_milliseconds, {service: @service_name})
      else
        @metrics.gauge("circuit_breaker.persistence.health", 0, {service: @service_name})
        Log.error { "Persistence health check failed: unable to read back test state" }
      end
      
    rescue ex : Exception
      duration = Time.monotonic - start_time
      @metrics.gauge("circuit_breaker.persistence.health", 0, {service: @service_name})
      @metrics.histogram("circuit_breaker.persistence.latency", duration.total_milliseconds, {service: @service_name})
      Log.error { "Persistence health check failed: #{ex.message}" }
    end
  end
end

# Usage
monitor = PersistenceHealthMonitor.new(persistence, "main_service")
```

---

This persistence setup guide provides comprehensive examples for implementing robust, production-ready persistence for H2O's circuit breaker functionality. Choose the appropriate persistence strategy based on your infrastructure, performance requirements, and operational constraints.