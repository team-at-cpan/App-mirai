requires 'parent', 0;
requires 'curry', 0;
requires 'Adapter::Async', '>= 0.011';
requires 'Variable::Disposition', 0;
requires 'Future', '>= 0.29';
requires 'Mixin::Event::Dispatch', '>= 1.006';
requires 'Tickit::DSL', '>= 0.021';
requires 'JSON::MaybeXS', 0;

requires 'Time::HiRes', 0;
requires 'File::Spec', 0;
requires 'List::UtilsBy', 0;
requires 'IO::Handle', 0;
requires 'File::HomeDir', '>= 1.00';
requires 'File::ShareDir', 0;

requires 'Socket', '>= 2.000';

recommends 'Sereal', '>= 3.000';

on 'test' => sub {
	requires 'Test::More', '>= 0.98';
	requires 'Test::Fatal', '>= 0.010';
	requires 'Test::Refcount', '>= 0.07';
};
