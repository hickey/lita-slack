require "spec_helper"

describe Lita::Adapters::Slack::RTMConnection, lita: true do
  def with_websocket(subject, queue)
    thread = Thread.new { subject.run(queue) }
    thread.abort_on_exception = true
    yield queue.pop
    subject.shut_down
    thread.join
  end

  subject { described_class.new(token, rtm_start_response) }

  let(:api) { instance_double("Lita::Adapters::Slack::API") }
  let(:rtm_start_response) do
    Lita::Adapters::Slack::RTMStartResponse.new(nil, [], [], "wss://example.com/")
  end
  let(:token) { 'abcd-1234567890-hWYd21AmMH2UHAkx29vb5c1Y' }
  let(:queue) { Queue.new }

  describe ".build" do
    before do
      allow(Lita::Adapters::Slack::API).to receive(:new).with(token).and_return(api)
      allow(api).to receive(:rtm_start).and_return(rtm_start_response)
    end

    it "constructs a new RTMConnection with the results of rtm.start data" do
      expect(described_class.build(token)).to be_an_instance_of(described_class)
    end

    it "creates users with the results of rtm.start data" do
      expect(Lita::Adapters::Slack::UserCreator).to receive(:create_users)

      described_class.build(token)
    end
  end

  describe "#run" do
    it "starts the reactor" do
      with_websocket(subject, queue) do |websocket|
        expect(EM.reactor_running?).to be_truthy
      end
    end

    it "creates the WebSocket" do
      with_websocket(subject, queue) do |websocket|
        expect(websocket).to be_an_instance_of(Faye::WebSocket::Client)
      end
    end
  end

  describe "#send_messages" do
    let(:message_json) { MultiJson.dump(id: 1, type: 'message', text: 'hi', channel: channel_id) }
    let(:channel_id) { 'C024BE91L' }
    let(:websocket) { instance_double("Faye::WebSocket::Client") }

    before do
      # TODO: Don't stub what you don't own!
      allow(Faye::WebSocket::Client).to receive(:new).and_return(websocket)
      allow(websocket).to receive(:on)
      allow(websocket).to receive(:close)
    end

    it "writes messages to the WebSocket" do
      with_websocket(subject, queue) do |websocket|
        expect(websocket).to receive(:send).with(message_json)

        subject.send_messages(channel_id, ['hi'])
      end
    end

    it "raises an ArgumentError if the payload is too large" do
      with_websocket(subject, queue) do |websocket|
        expect do
          subject.send_messages(channel_id, ['x' * 16_001])
        end.to raise_error(ArgumentError)
      end
    end
  end
end
