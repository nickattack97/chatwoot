require 'rails_helper'

RSpec.describe SafeFetch::AllowedInternalHosts do
  def uri(value)
    URI.parse(value)
  end

  describe '.allow?' do
    context 'when the env var is unset' do
      it 'allows nothing, so ssrf_filter keeps handling every host' do
        expect(described_class.allow?(uri('http://192.168.3.150:5005/hook'))).to be(false)
      end
    end

    context 'with a host:port entry' do
      before { stub_const('ENV', ENV.to_h.merge(described_class::ENV_KEY => '192.168.3.150:5005')) }

      it 'allows that exact host and port' do
        expect(described_class.allow?(uri('http://192.168.3.150:5005/hook'))).to be(true)
      end

      it 'refuses the same host on a different port' do
        expect(described_class.allow?(uri('http://192.168.3.150:9999/hook'))).to be(false)
      end

      it 'refuses a different host' do
        expect(described_class.allow?(uri('http://192.168.3.151:5005/hook'))).to be(false)
      end
    end

    context 'with a bare host entry' do
      before { stub_const('ENV', ENV.to_h.merge(described_class::ENV_KEY => 'internal.example')) }

      it 'allows any port on that host' do
        expect(described_class.allow?(uri('http://internal.example:8080/hook'))).to be(true)
        expect(described_class.allow?(uri('https://internal.example/hook'))).to be(true)
      end
    end

    context 'with a multi-entry list' do
      before do
        stub_const('ENV', ENV.to_h.merge(described_class::ENV_KEY => ' 192.168.3.150:5005 , internal.example '))
      end

      it 'trims whitespace around entries' do
        expect(described_class.allow?(uri('http://192.168.3.150:5005/hook'))).to be(true)
        expect(described_class.allow?(uri('http://internal.example/hook'))).to be(true)
      end

      it 'is case-insensitive on the hostname' do
        expect(described_class.allow?(uri('http://INTERNAL.EXAMPLE/hook'))).to be(true)
      end

      it 'still refuses anything not listed' do
        expect(described_class.allow?(uri('http://169.254.169.254/latest/meta-data'))).to be(false)
      end
    end
  end
end
