module H2O
  class BufferPool
    MAX_HEADER_BUFFER_SIZE = 64 * 1024
    MAX_FRAME_BUFFER_SIZE  = 16 * 1024 * 1024
    DEFAULT_POOL_SIZE      = 10

    @@header_buffers = Channel(Bytes).new(DEFAULT_POOL_SIZE)
    @@frame_buffers = Channel(Bytes).new(DEFAULT_POOL_SIZE)

    def self.get_header_buffer : Bytes
      select
      when buffer = @@header_buffers.receive?
        buffer || Bytes.new(MAX_HEADER_BUFFER_SIZE)
      else
        Bytes.new(MAX_HEADER_BUFFER_SIZE)
      end
    end

    def self.return_header_buffer(buffer : Bytes) : Nil
      return unless buffer.size == MAX_HEADER_BUFFER_SIZE

      select
      when @@header_buffers.send(buffer)
      else
        # Pool is full, let buffer be garbage collected
      end
    end

    def self.get_frame_buffer(size : Int32 = MAX_FRAME_BUFFER_SIZE) : Bytes
      if size <= MAX_FRAME_BUFFER_SIZE
        select
        when buffer = @@frame_buffers.receive?
          if buffer && buffer.size >= size
            # Return a slice of the requested size from the pooled buffer
            # but track the original buffer for proper return
            return buffer[0, size]
          else
            Bytes.new(size)
          end
        else
          Bytes.new(size)
        end
      else
        Bytes.new(size)
      end
    end

    def self.return_frame_buffer(buffer : Bytes) : Nil
      # Only return buffers that are the full size to maintain pool integrity
      return unless buffer.size == MAX_FRAME_BUFFER_SIZE

      select
      when @@frame_buffers.send(buffer)
      else
        # Pool is full, let buffer be garbage collected
      end
    end

    def self.with_header_buffer(& : Bytes -> T) : T forall T
      buffer = get_header_buffer
      begin
        yield buffer
      ensure
        return_header_buffer(buffer)
      end
    end

    def self.with_frame_buffer(size : Int32 = MAX_FRAME_BUFFER_SIZE, & : Bytes -> T) : T forall T
      if size <= MAX_FRAME_BUFFER_SIZE
        # Use pooled buffer for efficiency but provide requested size view
        select
        when pooled_buffer = @@frame_buffers.receive?
          if pooled_buffer
            begin
              yield pooled_buffer[0, size]
            ensure
              return_frame_buffer(pooled_buffer)
            end
          else
            buffer = Bytes.new(MAX_FRAME_BUFFER_SIZE)
            begin
              yield buffer[0, size]
            ensure
              return_frame_buffer(buffer)
            end
          end
        else
          buffer = Bytes.new(MAX_FRAME_BUFFER_SIZE)
          begin
            yield buffer[0, size]
          ensure
            return_frame_buffer(buffer)
          end
        end
      else
        # For large buffers, don't use pooling
        buffer = Bytes.new(size)
        yield buffer
      end
    end
  end
end
