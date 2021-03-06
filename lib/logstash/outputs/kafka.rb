require 'logstash/namespace'
require 'logstash/outputs/base'
require 'logstash-output-kafka_jars'

# Write events to a Kafka topic. This uses the Kafka Producer API to write messages to a topic on
# the broker.
#
# The only required configuration is the topic name. The default codec is json,
# so events will be persisted on the broker in json format. If you select a codec of plain,
# Logstash will encode your messages with not only the message but also with a timestamp and
# hostname. If you do not want anything but your message passing through, you should make the output
# configuration something like:
# [source,ruby]
#     output {
#       kafka {
#         codec => plain {
#            format => "%{message}"
#         }
#       }
#     }
# For more information see http://kafka.apache.org/documentation.html#theproducer
#
# Kafka producer configuration: http://kafka.apache.org/documentation.html#producerconfigs
class LogStash::Outputs::Kafka < LogStash::Outputs::Base
  config_name 'kafka'
  milestone 1

  default :codec, 'json'
  # This is for bootstrapping and the producer will only use it for getting metadata (topics,
  # partitions and replicas). The socket connections for sending the actual data will be
  # established based on the broker information returned in the metadata. The format is
  # `host1:port1,host2:port2`, and the list can be a subset of brokers or a VIP pointing to a
  # subset of brokers.
  config :broker_list, :validate => :string, :default => 'localhost:9092'
  # The topic to produce the messages to
  config :topic_id, :validate => :string, :required => true
  # This parameter allows you to specify the compression codec for all data generated by this
  # producer. Valid values are `none`, `gzip` and `snappy`.
  config :compression_codec, :validate => %w( none gzip snappy ), :default => 'none'
  # This parameter allows you to set whether compression should be turned on for particular
  # topics. If the compression codec is anything other than `NoCompressionCodec`,
  # enable compression only for specified topics if any. If the list of compressed topics is
  # empty, then enable the specified compression codec for all topics. If the compression codec
  # is `NoCompressionCodec`, compression is disabled for all topics
  config :compressed_topics, :validate => :string, :default => ''
  # This value controls when a produce request is considered completed. Specifically,
  # how many other brokers must have committed the data to their log and acknowledged this to the
  # leader. For more info, see -- http://kafka.apache.org/documentation.html#producerconfigs
  config :request_required_acks, :validate => [-1,0,1], :default => 0
  # The serializer class for messages. The default encoder takes a byte[] and returns the same byte[]
  config :serializer_class, :validate => :string, :default => 'kafka.serializer.StringEncoder'
  # The partitioner class for partitioning messages amongst partitions in the topic. The default
  # partitioner is based on the hash of the key. If the key is null,
  # the message is sent to a random partition in the broker.
  # NOTE: `topic_metadata_refresh_interval_ms` controls how long the producer will distribute to a
  # partition in the topic. This defaults to 10 mins, so the producer will continue to write to a
  # single partition for 10 mins before it switches
  config :partitioner_class, :validate => :string, :default => 'kafka.producer.DefaultPartitioner'
  # The amount of time the broker will wait trying to meet the `request.required.acks` requirement
  # before sending back an error to the client.
  config :request_timeout_ms, :validate => :number, :default => 10000
  # This parameter specifies whether the messages are sent asynchronously in a background thread.
  # Valid values are (1) async for asynchronous send and (2) sync for synchronous send. By
  # setting the producer to async we allow batching together of requests (which is great for
  # throughput) but open the possibility of a failure of the client machine dropping unsent data.
  config :producer_type, :validate => %w( sync async ), :default => 'sync'
  # The serializer class for keys (defaults to the same as for messages if nothing is given)
  config :key_serializer_class, :validate => :string, :default => nil
  # This property will cause the producer to automatically retry a failed send request. This
  # property specifies the number of retries when such failures occur. Note that setting a
  # non-zero value here can lead to duplicates in the case of network errors that cause a message
  # to be sent but the acknowledgement to be lost.
  config :message_send_max_retries, :validate => :number, :default => 3
  # Before each retry, the producer refreshes the metadata of relevant topics to see if a new
  # leader has been elected. Since leader election takes a bit of time,
  # this property specifies the amount of time that the producer waits before refreshing the
  # metadata.
  config :retry_backoff_ms, :validate => :number, :default => 100
  # The producer generally refreshes the topic metadata from brokers when there is a failure
  # (partition missing, leader not available...). It will also poll regularly (default: every
  # 10min so 600000ms). If you set this to a negative value, metadata will only get refreshed on
  # failure. If you set this to zero, the metadata will get refreshed after each message sent
  # (not recommended). Important note: the refresh happen only AFTER the message is sent,
  # so if the producer never sends a message the metadata is never refreshed
  config :topic_metadata_refresh_interval_ms, :validate => :number, :default => 600 * 1000
  # Maximum time to buffer data when using async mode. For example a setting of 100 will try to
  # batch together 100ms of messages to send at once. This will improve throughput but adds
  # message delivery latency due to the buffering.
  config :queue_buffering_max_ms, :validate => :number, :default => 5000
  # The maximum number of unsent messages that can be queued up the producer when using async
  # mode before either the producer must be blocked or data must be dropped.
  config :queue_buffering_max_messages, :validate => :number, :default => 10000
  # The amount of time to block before dropping messages when running in async mode and the
  # buffer has reached `queue.buffering.max.messages`. If set to 0 events will be enqueued
  # immediately or dropped if the queue is full (the producer send call will never block). If set
  # to -1 the producer will block indefinitely and never willingly drop a send.
  config :queue_enqueue_timeout_ms, :validate => :number, :default => -1
  # The number of messages to send in one batch when using async mode. The producer will wait
  # until either this number of messages are ready to send or `queue.buffer.max.ms` is reached.
  config :batch_num_messages, :validate => :number, :default => 200
  # Socket write buffer size
  config :send_buffer_bytes, :validate => :number, :default => 100 * 1024
  # The client id is a user-specified string sent in each request to help trace calls. It should
  # logically identify the application making the request.
  config :client_id, :validate => :string, :default => ''

  public
  def register
    require 'jruby-kafka'
    options = {
        :broker_list => @broker_list,
        :compression_codec => @compression_codec,
        :compressed_topics => @compressed_topics,
        :request_required_acks => @request_required_acks,
        :serializer_class => @serializer_class,
        :partitioner_class => @partitioner_class,
        :request_timeout_ms => @request_timeout_ms,
        :producer_type => @producer_type,
        :key_serializer_class => @key_serializer_class,
        :message_send_max_retries => @message_send_max_retries,
        :retry_backoff_ms => @retry_backoff_ms,
        :topic_metadata_refresh_interval_ms => @topic_metadata_refresh_interval_ms,
        :queue_buffering_max_ms => @queue_buffering_max_ms,
        :queue_buffering_max_messages => @queue_buffering_max_messages,
        :queue_enqueue_timeout_ms => @queue_enqueue_timeout_ms,
        :batch_num_messages => @batch_num_messages,
        :send_buffer_bytes => @send_buffer_bytes,
        :client_id => @client_id
    }
    @producer = Kafka::Producer.new(options)
    @producer.connect

    @logger.info('Registering kafka producer', :topic_id => @topic_id, :broker_list => @broker_list)

    @codec.on_event do |event, data|
      begin
        @producer.send_msg(@topic_id,nil,data)
      rescue LogStash::ShutdownSignal
        @logger.info('Kafka producer got shutdown signal')
      rescue => e
        @logger.warn('kafka producer threw exception, restarting',
                     :exception => e)
      end
    end
  end # def register

  def receive(event)
    return unless output?(event)
    if event == LogStash::SHUTDOWN
      finished
      return
    end
    @codec.encode(event)
  end

  def teardown
    @producer.close
  end
end #class LogStash::Outputs::Kafka
