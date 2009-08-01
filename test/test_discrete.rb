#!/usr/bin/env ruby

require 'redshift'

include RedShift

=begin

This file tests discrete features of RedShift, such as transitions and events. Inheritance of discrete behavior is tested separately in test_interit*.rb.

=end

class DiscreteTestComponent < Component
  def initialize(*args)
    super
    @t = world.clock
  end
end

# Enter is the default starting state

class Discrete_1 < DiscreteTestComponent
  def assert_consistent test
    test.assert_equal(state, Enter)
  end
end

# Transitions are Enter => Enter by default

class Discrete_1_1 < DiscreteTestComponent
  transition do
    guard {not @check}
    action {@check = true}
  end
  def assert_consistent test
    test.assert(@check == true)
  end
end

# Exit causes the component to leave the world

class Discrete_2 < DiscreteTestComponent
  def initialize(*args)
    super
    @prev_world = world
  end
  transition Enter => Exit
  def assert_consistent test
    test.assert_equal(Exit, state)
    test.assert_nil(world)
    test.assert_nil(@prev_world.find {|c| c == self})
  end
end

# 'start <state>' sets the start state, but fails after initialization

class Discrete_3 < DiscreteTestComponent
  state :A
  default { start A }
  def assert_consistent test
    test.assert_equal(A, state)
    test.assert_raises(AlreadyStarted) {start A}
  end
end

class Discrete_4a < DiscreteTestComponent
  state :A, :B; default { start A }
  transition A => B do
    name "zap"
    event :e
    pass
      ## pass because, as an optimization, a component finishes the transition
      ## after completing the last phase, rather than at the end of the
      ## discrete step.
  end
end

class Discrete_4b < DiscreteTestComponent
  state :A, :B; default { start A }
  transition A => B do
    guard { 
      # during guard evaluation, the transition emitting e is still active
      if @x.e
        @x_state_during = @x.state.name
        @x_trans_during = @x.active_transition
      end
      @x.e
    }
    pass
  end
  setup { @x = create Discrete_4a }
  def assert_consistent test
    test.assert_equal(B, state)
    test.assert_equal("A", @x_state_during.to_s)
    test.assert_equal("zap", @x_trans_during.name)
    test.assert_equal("B", @x.state.name.to_s)
    test.assert_nil(@x.active_transition)
    test.assert_nil(@x_e_after)
  end
end

# event value is true by default, and nil when not exported

class Discrete_5a < DiscreteTestComponent
  transition Enter => Exit do event :e end
end

class Discrete_5b < DiscreteTestComponent
  transition do
    guard {@x.e && @x_e = @x.e}  # note assignment
  end
  setup { @x = create Discrete_5a }
  def assert_consistent test
    test.assert_equal(true, @x_e)
    test.assert_equal(nil, @x.e)
  end
end

# event value can be supplied statically...

class Discrete_6a < DiscreteTestComponent
  EventValue = [[3.75], {1 => :foo}]
  transition Enter => Exit do
    event :e => EventValue
  end
end

class Discrete_6b < DiscreteTestComponent
  transition do
    guard {@x.e}
    action {@x_e = @x.e}
  end
  setup { @x = create Discrete_6a }
  def assert_consistent test
    test.assert_equal(Discrete_6a::EventValue, @x_e)
  end
end

# ...or dynamically

class Discrete_7a < DiscreteTestComponent
  EventValue = [[3.75], {1 => :foo}]
  transition Enter => Exit do
    event {
      e {EventValue}
    }
  end
end

class Discrete_7b < DiscreteTestComponent
  transition do
    guard {@x.e}
    action {@x_e = @x.e}
  end
  setup { @x = create Discrete_7a }
  def assert_consistent test
    test.assert_equal(Discrete_7a::EventValue, @x_e)
  end
end

# a guard testing for event doesn't need a block

class Discrete_8a < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    event :e
  end
  transition A => B do
    event :f => 2.3
  end
end

class Discrete_8b < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    guard :x => :e
  end
  transition A => B do
    guard [:x, :f]    # alt. syntax, in future will allow value
    action {@x_f = x.f}
  end
  link :x => Discrete_8a
  setup { self.x = create Discrete_8a }
  def assert_consistent test
    test.assert_equal(B, state)
    test.assert_equal(2.3, @x_f)
  end
end

# multiple guard terms are implicitly AND-ed

class Discrete_9a < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    event :e
  end
  transition A => B do
    event :f
  end
end

class Discrete_9b < DiscreteTestComponent
  state :A, :B, :C
  transition Enter => A do
    guard :x => :e
  end
  transition A => B do
    guard [:x, :f], :x => :e      # x.f AND x.e
  end
  transition A => C do
    guard [:x, :f] do false end   # x.f AND FALSE
  end
  link :x => Discrete_9a
  setup { self.x = create Discrete_9a }
  def assert_consistent test
    test.assert_equal(A, state)
  end
end

# test C expressions as guards

class Discrete_10a < DiscreteTestComponent
  state :A, :B
  continuous :v
  transition Enter => A do
    action {self.v = 1}
  end
  transition A => B do
    action {self.v = 2}
  end
end

class Discrete_10b < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    guard "x.v == 1"
  end
  transition A => B do
    guard "x.v == 3"
  end
  link :x => Discrete_10a
  setup { self.x = create Discrete_10a }
  def assert_consistent test
    test.assert_equal(A, state)
  end
end

# multiple guard terms with C exprs

class Discrete_11a < DiscreteTestComponent
  state :A, :B
  continuous :v
  transition Enter => A do
    action {self.v = 1}
  end
  transition A => B do
    action {self.v = 2}
    event :e
  end
end

class Discrete_11b < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    guard "x.v == 1", "0"
  end
  transition Enter => A do
    guard "x.v == 1", :x => :e
  end
  transition Enter => A do
    guard "x.v == 1" do false end
  end
  link :x => Discrete_11a
  setup { self.x = create Discrete_11a }
  def assert_consistent test
    test.assert_equal(Enter, state)
  end
end

# testing for an event in link which is nil is false

class Discrete_12a < DiscreteTestComponent
  transition do
    event :e
  end
end

class Discrete_12b < DiscreteTestComponent
  link :comp => Discrete_12a
  transition Enter => Exit do
    guard :comp => :e
  end
  def assert_consistent test
    test.assert_equal(Enter, state)
  end
end

# test when the state actually changes during a transition
# (to wit, after the last clause)

class Discrete_13 < DiscreteTestComponent
  state :A1, :A2
  start A1
  flow A1 do alg "var = 1" end
  flow A2 do alg "var = 2" end
  transition A1 => A2 do
    action {@x = var}
    action {@xx = var}
  end
  transition A2 => Exit do
    action {@y = var}
    action {@yy = var}
  end
  def assert_consistent test
    test.assert_equal(1, @x)
    test.assert_equal(1, @xx)
    test.assert_equal(2, @y)
    test.assert_equal(2, @yy)
  end
end

# test that resets and events happen in parallel

class Discrete_14 < DiscreteTestComponent
  state :A1, :A2
  continuous :x, :y, :z
  link :other => self

  default {start A1}
  setup { self.other ||= create(self.class) {|c| start A2; c.other = self} }

  transition A1 => Exit do
    reset :x => 1
    event :e => proc { other.x }
  end
  transition A2 => Exit do
    reset :x => 2
    reset :x => proc { other.e.to_i }
    reset :y => proc { other.e.to_i }
    reset :z => proc { other.e.to_i }
  end

  def assert_consistent test
    case start_state
    when A1
      test.assert_equal(1, x)
      test.assert_equal(0, y)
      test.assert_equal(0, z)
    when A2
      test.assert_equal(0, x)
      test.assert_equal(2, y)
      test.assert_equal(0, z)
    else
      test.flunk
    end
  end
end

# multiple simultaneous events

class Discrete_15a < DiscreteTestComponent
  transition Enter => Exit do
    event {e; f}
  end
end

class Discrete_15b < DiscreteTestComponent
  link :x => Discrete_15a
  setup { self.x = create Discrete_15a }
  transition Enter => Exit do
    guard :x => :e, :x => :f
  end
  def assert_consistent test
    test.assert_equal(Exit, state)
  end
end

# priority of transitions is based on program text

class Discrete_16 < DiscreteTestComponent
  state :S
  transition(Enter => S) {action {@pass=true}}
  transition(Enter => S) {action {@pass=false}}
  transition(Enter => S) {action {@pass=false}}
  def assert_consistent test
    test.flunk("transitions are not in priority order") unless @pass
  end
end

=begin

test timing of other combinations of
  action, guard, event, reset

test guard phases

=end

#-----#

require 'test/unit'

class TestDiscrete < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step = 0.1
  end
  
  def teardown
    @world = nil
  end
  
  def test_discrete
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= DiscreteTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    @world.run
    
    for t in testers
      t.assert_consistent self
    end
  end
end
