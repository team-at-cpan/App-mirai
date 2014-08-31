requires 'parent', 0;
requires 'curry', 0;
requires 'Variable::Disposition', 0;
requires 'Future', '>= 0.29';
requires 'Mixin::Event::Dispatch', '>= 1.006';
requires 'Tickit::DSL', '>= 0.020';
requires 'File::HomeDir', '>= 1.00';
requires 'JSON::MaybeXS', 0;
requires 'Sereal', '>= 3.000';

on 'test' => sub {
	requires 'Test::More', '>= 0.98';
	requires 'Test::Fatal', '>= 0.010';
	requires 'Test::Refcount', '>= 0.07';
};

