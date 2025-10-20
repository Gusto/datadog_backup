# frozen_string_literal: true

require 'spec_helper'

describe DatadogBackup::Workflows do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:api_client_double) { Faraday.new { |f| f.adapter :test, stubs } }
  let(:tempdir) { Dir.mktmpdir }
  let(:workflows) do
    workflows = described_class.new(
      action: 'backup',
      backup_dir: tempdir,
      output_format: :json,
      resources: []
    )
    allow(workflows).to receive(:api_service).and_return(api_client_double)
    return workflows
  end
  let(:workflow_abc_123) do
    {
      'id' => 'abc-123-def',
      'attributes' => {
        'name' => 'Test Workflow',
        'description' => 'A test workflow for CI/CD',
        'steps' => [
          {
            'name' => 'step_1',
            'action' => 'com.datadoghq.http',
            'params' => {
              'url' => 'https://example.com/api',
              'method' => 'POST'
            }
          }
        ],
        'triggers' => [
          {
            'type' => 'schedule',
            'schedule' => '0 9 * * 1-5'
          }
        ]
      },
      'created_at' => '2024-01-01T00:00:00Z',
      'modified_at' => '2024-01-02T00:00:00Z',
      'last_executed_at' => '2024-01-03T00:00:00Z'
    }
  end
  let(:workflow_xyz_456) do
    {
      'id' => 'xyz-456-ghi',
      'attributes' => {
        'name' => 'Another Workflow',
        'description' => 'Another test workflow',
        'steps' => [],
        'triggers' => []
      },
      'created_at' => '2024-02-01T00:00:00Z',
      'modified_at' => '2024-02-02T00:00:00Z'
    }
  end
  let(:workflow_abc_123_clean) do
    {
      'data' => {
        'type' => 'workflows',
        'id' => 'abc-123-def',
        'attributes' => {
          'name' => 'Test Workflow',
          'description' => 'A test workflow for CI/CD',
          'steps' => [
            {
              'name' => 'step_1',
              'action' => 'com.datadoghq.http',
              'params' => {
                'url' => 'https://example.com/api',
                'method' => 'POST'
              }
            }
          ],
          'triggers' => [
            {
              'type' => 'schedule',
              'schedule' => '0 9 * * 1-5'
            }
          ]
        }
      }
    }
  end
  let(:workflow_xyz_456_clean) do
    {
      'data' => {
        'type' => 'workflows',
        'id' => 'xyz-456-ghi',
        'attributes' => {
          'name' => 'Another Workflow',
          'description' => 'Another test workflow',
          'steps' => [],
          'triggers' => []
        }
      }
    }
  end
  let(:fetched_workflows) do
    {
      'data' => [workflow_abc_123, workflow_xyz_456]
    }
  end
  let(:workflow_abc_123_response) do
    { 'data' => workflow_abc_123 }
  end
  let(:workflow_xyz_456_response) do
    { 'data' => workflow_xyz_456 }
  end
  let(:all_workflows) { respond_with200(fetched_workflows) }
  let(:example_workflow1) { respond_with200(workflow_abc_123_response) }
  let(:example_workflow2) { respond_with200(workflow_xyz_456_response) }

  before do
    stubs.get('/api/v2/workflows') { all_workflows }
    stubs.get('/api/v2/workflows/abc-123-def') { example_workflow1 }
    stubs.get('/api/v2/workflows/xyz-456-ghi') { example_workflow2 }
  end

  after do
    FileUtils.remove_entry tempdir
  end

  describe '#backup' do
    subject { workflows.backup }

    it 'is expected to create two files' do
      file1 = instance_double(File)
      allow(File).to receive(:open).with(workflows.filename('abc-123-def'), 'w').and_return(file1)
      allow(file1).to receive(:write)
      allow(file1).to receive(:close)

      file2 = instance_double(File)
      allow(File).to receive(:open).with(workflows.filename('xyz-456-ghi'), 'w').and_return(file2)
      allow(file2).to receive(:write)
      allow(file2).to receive(:close)

      workflows.backup
      expect(file1).to have_received(:write).with(::JSON.pretty_generate(workflow_abc_123_clean.deep_sort))
      expect(file2).to have_received(:write).with(::JSON.pretty_generate(workflow_xyz_456_clean.deep_sort))
    end
  end

  describe '#filename' do
    subject { workflows.filename('abc-123-def') }

    it { is_expected.to eq("#{tempdir}/workflows/abc-123-def.json") }
  end

  describe '#get_by_id' do
    subject { workflows.get_by_id('abc-123-def') }

    it { is_expected.to eq workflow_abc_123_clean }
  end

  describe '#all' do
    subject { workflows.all }

    it 'returns array of workflows' do
      expect(subject).to eq([workflow_abc_123, workflow_xyz_456])
    end
  end

  describe '#diff' do
    it 'calls the api only once' do
      workflows.write_file('{"a":"b"}', workflows.filename('abc-123-def'))
      expect(workflows.diff('abc-123-def')).to eq(<<~EODASH
         ---
        -data:
        -  attributes:
        -    description: A test workflow for CI/CD
        -    name: Test Workflow
        -    steps:
        -    - action: com.datadoghq.http
        -      name: step_1
        -      params:
        -        method: POST
        -        url: https://example.com/api
        -    triggers:
        -    - schedule: 0 9 * * 1-5
        -      type: schedule
        -  id: abc-123-def
        -  type: workflows
        +a: b
      EODASH
      .chomp)
    end
  end

  describe '#except' do
    subject { workflows.except({ :a => :b, 'created_at' => :c, 'modified_at' => :d, 'last_executed_at' => :e }) }

    it { is_expected.to eq({ a: :b }) }
  end

  describe 'private methods' do
    it 'uses v2 API' do
      expect(workflows.send(:api_version)).to eq('v2')
    end

    it 'uses workflows resource name' do
      expect(workflows.send(:api_resource_name)).to eq('workflows')
    end

    it 'uses id as id_keyname' do
      expect(workflows.send(:id_keyname)).to eq('id')
    end
  end
end
