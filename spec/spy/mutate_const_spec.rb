require 'spec_helper'

TOP_LEVEL_VALUE_CONST = 7

class TestClass
  M = :m
  N = :n

  class Nested
    class NestedEvenMore
    end
  end
end

class TestSubClass < TestClass
  P = :p
end

module Spy
  describe "Constant Mutating" do

    def reset_rspec_mocks
      Spy.teardown
    end

    def on_const(const_name)
      if const_name.include? "::"
      args = [recursive_const_get("Object::" + const_name.sub(/(::)?[^:]+\z/, '')), const_name.split('::').last.to_sym]
      else
        args = [const_name.to_sym]
      end
      Spy.get_const(*args) || Spy.on_const(*args)
    end

    def stub_const(const_name, value)
      on_const(const_name).and_return(value)
      value
    end

    def hide_const(const_name)
      on_const(const_name).and_hide
    end

    shared_context "constant example methods" do |const_name|
      define_method :const do
        recursive_const_get(const_name)
      end

      define_method :parent_const do
        recursive_const_get("Object::" + const_name.sub(/(::)?[^:]+\z/, ''))
      end

      define_method :last_const_part do
        const_name.split('::').last
      end
    end

    shared_examples_for "loaded constant stubbing" do |const_name|
      include_context "constant example methods", const_name

      let!(:original_const_value) { const }
      after { change_const_value_to(original_const_value) }

      def change_const_value_to(value)
        parent_const.send(:remove_const, last_const_part)
        parent_const.const_set(last_const_part, value)
      end

      it 'allows it to be stubbed' do
        expect(const).not_to eq(7)
        stub_const(const_name, 7)
        expect(const).to eq(7)
      end

      it 'resets it to its original value when rspec clears its mocks' do
        original_value = const
        expect(original_value).not_to eq(:a)
        stub_const(const_name, :a)
        reset_rspec_mocks
        expect(const).to be(original_value)
      end

      it 'returns the stubbed value' do
        expect(stub_const(const_name, 7)).to eq(7)
      end
    end

    shared_examples_for "loaded constant hiding" do |const_name|
      before do
        expect(recursive_const_defined?(const_name)).to be_true
      end

      it 'allows it to be hidden' do
        hide_const(const_name)
        expect(recursive_const_defined?(const_name)).to be_false
      end

      it 'resets the constant when rspec clear its mocks' do
        hide_const(const_name)
        reset_rspec_mocks
        expect(recursive_const_defined?(const_name)).to be_true
      end

      it 'returns nil' do
        expect(hide_const(const_name)).to be_nil
      end
    end

    shared_examples_for "unloaded constant stubbing" do |const_name|
      include_context "constant example methods", const_name

      before do
        expect(recursive_const_defined?(const_name)).to be_false
      end

      it 'allows it to be stubbed' do
        stub_const(const_name, 7)
        expect(const).to eq(7)
      end

      it 'removes the constant when rspec clears its mocks' do
        stub_const(const_name, 7)
        reset_rspec_mocks
        expect(recursive_const_defined?(const_name)).to be_false
      end

      it 'returns the stubbed value' do
        expect(stub_const(const_name, 7)).to eq(7)
      end

      it 'ignores the :transfer_nested_constants option if passed' do
        stub = Module.new
        stub_const(const_name, stub, :transfer_nested_constants => true)
        expect(stub.constants).to eq([])
      end
    end

    shared_examples_for "unloaded constant hiding" do |const_name|
      include_context "constant example methods", const_name

      before do
        expect(recursive_const_defined?(const_name)).to be_false
      end

      it 'allows it to be hidden, though the operation has no effect' do
        hide_const(const_name)
        expect(recursive_const_defined?(const_name)).to be_false
      end

      it 'remains undefined after rspec clears its mocks' do
        hide_const(const_name)
        reset_rspec_mocks
        expect(recursive_const_defined?(const_name)).to be_false
      end

      it 'returns nil' do
        expect(hide_const(const_name)).to be_nil
      end
    end

    describe "#hide_const" do
      context 'for a loaded nested constant' do
        it_behaves_like "loaded constant hiding", "TestClass::Nested"
      end

      context 'for a loaded constant prefixed with ::' do
        it_behaves_like 'loaded constant hiding', "::TestClass"
      end

      context 'for an unloaded constant with nested name that matches a top-level constant' do
        it_behaves_like "unloaded constant hiding", "TestClass::Hash"

        it 'does not hide the top-level constant' do
          expect {
            hide_const("TestClass::Hash")
          }.to raise_error
        end
      end

      context 'for a loaded deeply nested constant' do
        it_behaves_like "loaded constant hiding", "TestClass::Nested::NestedEvenMore"
      end

      context 'for an unloaded unnested constant' do
        it_behaves_like "unloaded constant hiding", "X"
      end

      context 'for an unloaded nested constant' do
        it_behaves_like "unloaded constant hiding", "X::Y"
      end

      it 'can be hidden multiple times but still restores the original value properly' do
        orig_value = TestClass
        hide_const("TestClass")
        hide_const("TestClass")

        reset_rspec_mocks
        expect(TestClass).to be(orig_value)
      end

      it 'allows a constant to be hidden, then stubbed, restoring it to its original value properly' do
        orig_value = TOP_LEVEL_VALUE_CONST

        hide_const("TOP_LEVEL_VALUE_CONST")
        expect(recursive_const_defined?("TOP_LEVEL_VALUE_CONST")).to be_false

        stub_const("TOP_LEVEL_VALUE_CONST", 12345)
        expect(TOP_LEVEL_VALUE_CONST).to eq 12345

        reset_rspec_mocks
        expect(TOP_LEVEL_VALUE_CONST).to eq orig_value
      end
    end

    describe "#stub_const" do
      context 'for a loaded unnested constant' do
        it_behaves_like "loaded constant stubbing", "TestClass"

        it 'can be stubbed multiple times but still restores the original value properly' do
          orig_value = TestClass
          stub1, stub2 = Module.new, Module.new
          stub_const("TestClass", stub1)
          stub_const("TestClass", stub2)

          reset_rspec_mocks
          expect(TestClass).to be(orig_value)
        end

        it 'allows nested constants to be transferred to a stub module' do
          tc_nested = TestClass::Nested
          stub = Module.new
          stub_const("TestClass", stub, :transfer_nested_constants => true)
          expect(stub::M).to eq(:m)
          expect(stub::N).to eq(:n)
          expect(stub::Nested).to be(tc_nested)
        end

        it 'does not transfer nested constants that are inherited from a superclass' do
          stub = Module.new
          stub_const("TestSubClass", stub, :transfer_nested_constants => true)
          expect(stub::P).to eq(:p)
          expect(defined?(stub::M)).to be_false
          expect(defined?(stub::N)).to be_false
        end

        it 'raises an error when asked to transfer a nested inherited constant' do
          original_tsc = TestSubClass

          expect {
            stub_const("TestSubClass", Module.new, :transfer_nested_constants => [:M])
          }.to raise_error(ArgumentError)

          expect(TestSubClass).to be(original_tsc)
        end

        it 'allows nested constants to be selectively transferred to a stub module' do
          stub = Module.new
          stub_const("TestClass", stub, :transfer_nested_constants => [:M, :N])
          expect(stub::M).to eq(:m)
          expect(stub::N).to eq(:n)
          expect(defined?(stub::Nested)).to be_false
        end

        it 'raises an error if asked to transfer nested constants but given an object that does not support them' do
          original_tc = TestClass
          stub = Object.new
          expect {
            stub_const("TestClass", stub, :transfer_nested_constants => true)
          }.to raise_error(ArgumentError)

          expect(TestClass).to be(original_tc)

          expect {
            stub_const("TestClass", stub, :transfer_nested_constants => [:M])
          }.to raise_error(ArgumentError)

          expect(TestClass).to be(original_tc)
        end

        it 'raises an error if asked to transfer nested constants on a constant that does not support nested constants' do
          stub = Module.new
          expect {
            stub_const("TOP_LEVEL_VALUE_CONST", stub, :transfer_nested_constants => true)
          }.to raise_error(ArgumentError)

          expect(TOP_LEVEL_VALUE_CONST).to eq(7)

          expect {
            stub_const("TOP_LEVEL_VALUE_CONST", stub, :transfer_nested_constants => [:M])
          }.to raise_error(ArgumentError)

          expect(TOP_LEVEL_VALUE_CONST).to eq(7)
        end

        it 'raises an error if asked to transfer a nested constant that is not defined' do
          original_tc = TestClass
          expect(defined?(TestClass::V)).to be_false
          stub = Module.new

          expect {
            stub_const("TestClass", stub, :transfer_nested_constants => [:V])
          }.to raise_error(/cannot transfer nested constant.*V/i)

          expect(TestClass).to be(original_tc)
        end
      end

      context 'for a loaded nested constant' do
        it_behaves_like "loaded constant stubbing", "TestClass::Nested"
      end

      context 'for an unloaded constant with nested name that matches a top-level constant' do
        it_behaves_like "unloaded constant stubbing", "TestClass::Hash"
      end

      context 'for a loaded deeply nested constant' do
        it_behaves_like "loaded constant stubbing", "TestClass::Nested::NestedEvenMore"
      end

      context 'for an unloaded unnested constant' do
        it_behaves_like "unloaded constant stubbing", "X"
      end

      context 'for an unloaded constant nested within a loaded constant' do
        it_behaves_like "unloaded constant stubbing", "TestClass::X"

        it 'removes the unloaded constant but leaves the loaded constant when rspec resets its mocks' do
          expect(defined?(TestClass)).to be_true
          expect(defined?(TestClass::X)).to be_false
          stub_const("TestClass::X", 7)
          reset_rspec_mocks
          expect(defined?(TestClass)).to be_true
          expect(defined?(TestClass::X)).to be_false
        end

        it 'raises a helpful error if it cannot be stubbed due to an intermediary constant that is not a module' do
          expect(TestClass::M).to be_a(Symbol)
          expect { stub_const("TestClass::M::X", 5) }.to raise_error(/cannot stub/i)
        end
      end

      context 'for an unloaded constant nested deeply within a deeply nested loaded constant' do
        it_behaves_like "unloaded constant stubbing", "TestClass::Nested::NestedEvenMore::X::Y::Z"

        it 'removes the first unloaded constant but leaves the loaded nested constant when rspec resets its mocks' do
          expect(defined?(TestClass::Nested::NestedEvenMore)).to be_true
          expect(defined?(TestClass::Nested::NestedEvenMore::X)).to be_false
          stub_const("TestClass::Nested::NestedEvenMore::X::Y::Z", 7)
          reset_rspec_mocks
          expect(defined?(TestClass::Nested::NestedEvenMore)).to be_true
          expect(defined?(TestClass::Nested::NestedEvenMore::X)).to be_false
        end
      end
    end
  end

  describe Constant do
    def reset_rspec_mocks
      Spy.teardown
    end

    def on_const(const_name)
      if const_name.include? "::"
      args = [recursive_const_get("Object::" + const_name.sub(/(::)?[^:]+\z/, '')), const_name.split('::').last.to_sym]
      else
        args = [const_name.to_sym]
      end
      Spy.get_const(*args) || Spy.on_const(*args)
    end

    def stub_const(const_name, value)
      on_const(const_name).and_return(value)
    end

    def hide_const(const_name)
      on_const(const_name).and_hide
    end

    def original(const_name)
      if const_name.include? "::"
      args = [recursive_const_get("Object::" + const_name.sub(/(::)?[^:]+\z/, '')), const_name.split('::').last.to_sym]
      else
        args = [const_name.to_sym]
      end
      Spy.get_const(*args)
    end

    describe ".original" do
      context 'for a previously defined unstubbed constant' do
        let(:const) { original("TestClass::M") }

        it("exposes its name")                    { expect(const.name).to eq("TestClass::M") }
        it("indicates it was previously defined") { expect(const).to be_previously_defined }
        it("indicates it has not been hidden")    { expect(const).not_to be_hidden }
        it("exposes its original value")          { expect(const.original_value).to eq(:m) }
      end

      context 'for a previously defined stubbed constant' do
        before { stub_const("TestClass::M", :other) }
        let(:const) { original("TestClass::M") }

        it("exposes its name")                    { expect(const.name).to eq("TestClass::M") }
        it("indicates it was previously defined") { expect(const).to be_previously_defined }
        it("indicates it has not been hidden")    { expect(const).not_to be_hidden }
        it("exposes its original value")          { expect(const.original_value).to eq(:m) }
      end

      context 'for a previously undefined stubbed constant' do
        before { stub_const("TestClass::Undefined", :other) }
        let(:const) { original("TestClass::Undefined") }

        it("exposes its name")                        { expect(const.name).to eq("TestClass::Undefined") }
        it("indicates it was not previously defined") { expect(const).not_to be_previously_defined }
        it("indicates it has not been hidden")        { expect(const).not_to be_hidden }
        it("returns nil for the original value")      { expect(const.original_value).to be_nil }
      end

      context 'for a previously undefined unstubbed constant' do
        let(:const) { original("TestClass::Undefined") }

        it("exposes its name")                        { expect(const.name).to eq("TestClass::Undefined") }
        it("indicates it was not previously defined") { expect(const).not_to be_previously_defined }
        it("indicates it has not been hidden")        { expect(const).not_to be_hidden }
        it("returns nil for the original value")      { expect(const.original_value).to be_nil }
      end

      context 'for a previously defined constant that has been stubbed twice' do
        before { stub_const("TestClass::M", 1) }
        before { stub_const("TestClass::M", 2) }
        let(:const) { original("TestClass::M") }

        it("exposes its name")                    { expect(const.name).to eq("TestClass::M") }
        it("indicates it was previously defined") { expect(const).to be_previously_defined }
        it("indicates it has not been hidden")    { expect(const).not_to be_hidden }
        it("exposes its original value")          { expect(const.original_value).to eq(:m) }
      end

      context 'for a previously undefined constant that has been stubbed twice' do
        before { stub_const("TestClass::Undefined", 1) }
        before { stub_const("TestClass::Undefined", 2) }
        let(:const) { original("TestClass::Undefined") }

        it("exposes its name")                        { expect(const.name).to eq("TestClass::Undefined") }
        it("indicates it was not previously defined") { expect(const).not_to be_previously_defined }
        it("indicates it has not been hidden")        { expect(const).not_to be_hidden }
        it("returns nil for the original value")      { expect(const.original_value).to be_nil }
      end

      context 'for a previously defined hidden constant' do
        before { hide_const("TestClass::M") }
        let(:const) { original("TestClass::M") }

        it("exposes its name")                    { expect(const.name).to eq("TestClass::M") }
        it("indicates it was previously defined") { expect(const).to be_previously_defined }
        it("indicates it has been hidden")        { expect(const).to be_hidden }
        it("exposes its original value")          { expect(const.original_value).to eq(:m) }
      end

      context 'for a previously defined constant that has been hidden twice' do
        before { hide_const("TestClass::M") }
        before { hide_const("TestClass::M") }
        let(:const) { original("TestClass::M") }

        it("exposes its name")                    { expect(const.name).to eq("TestClass::M") }
        it("indicates it was previously defined") { expect(const).to be_previously_defined }
        it("indicates it has been hidden")        { expect(const).to be_hidden }
        it("exposes its original value")          { expect(const.original_value).to eq(:m) }
      end
    end
  end
end
