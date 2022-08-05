#!/usr/bin/perl

requires 'Net::SSLeay';
requires 'X::Tiny';
requires 'Protocol::HTTP2';
requires 'Scalar::Util';
requires 'URI::Split';
requires 'Promise::ES6';

on test => sub {
    requires 'Test::More';
    requires 'Test::FailWarnings';

    recommends 'AnyEvent';
};
