%%==============================================================================
%% Copyright 2011 Erlang Solutions Ltd.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================
-module(private_SUITE).
-compile(export_all).

-include_lib("exml/include/exml.hrl").
-include_lib("escalus/include/escalus.hrl").
-include_lib("common_test/include/ct.hrl").

%%--------------------------------------------------------------------
%% Suite configuration
%%--------------------------------------------------------------------
all() ->
    [{group, private_positive},
     {group, private_negative}].

groups() ->
     [{private_positive, [sequence], [store_retrieve]},
      {private_negative, [sequence], [get_other_user,
                                      set_other_user]}].
                                      %% FIXME: broken exmpp prevents us from sending
                                      %% out elements without NS set
                                      %% missing_ns]}].

suite() ->
    escalus:suite().

init_per_suite(Config) ->
    escalus:init_per_suite(Config).

end_per_suite(Config) ->
    escalus:end_per_suite(Config).

init_per_group(_GroupName, Config) ->
    escalus:create_users(Config).

end_per_group(_GroupName, Config) ->
    escalus:delete_users(Config).

init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).

%%--------------------------------------------------------------------
%% Private storage tests
%%--------------------------------------------------------------------
store_retrieve(Config) ->
    escalus:story(Config, [1],
                  fun(Alice) ->
                          NS = <<"alice:private:ns">>,

                          %% Alice stores some data in her private storage
                          escalus_client:send(Alice, escalus_stanza:private_set(my_banana(NS))),

                          %% Alice receives store confirmation
                          escalus:assert(is_private_result, escalus_client:wait_for_stanza(Alice)),

                          %% Alice asks for the data
                          escalus_client:send(Alice, escalus_stanza:private_get(NS, <<"my_element">>)),

                          %% Alice ensures data has not been changed
                          Stanza = escalus_client:wait_for_stanza(Alice),
                          escalus:assert(is_private_result, Stanza),
                          check_body(Stanza, [<<"my_element">>, <<"banana">>]),

                          %% Alice asks for non-existing data
                          escalus_client:send(Alice, escalus_stanza:private_get(<<"non_existing_ns">>,
                                                                                <<"my_element">>)),

                          %% Alice receives an empty response
                          Stanza2 = escalus_client:wait_for_stanza(Alice),
                          escalus:assert(is_private_result, Stanza2),
                          check_body(Stanza, [<<"my_element">>])
                  end).

get_other_user(Config) ->
    escalus:story(Config, [1, 1],
                  fun(Alice, _Bob) ->
                          NS = <<"bob:private:ns">>,

                          %% Alice asks for Bob's private data
                          GetIQ = escalus_stanza:private_get(NS, <<"my_element">>),
                          IQ = escalus_stanza:to(GetIQ, bob),
                          escalus_client:send(Alice, IQ),

                          %% Alice gets an error
                          Stanza = escalus_client:wait_for_stanza(Alice),
                          escalus:assert(is_private_error, Stanza),
                          escalus_pred:is_error(<<"cancel">>, forbidden, Stanza)
                  end).

set_other_user(Config) ->
    escalus:story(Config, [1, 1],
                  fun(Alice, _Bob) ->
                          NS = <<"bob:private:ns">>,

                          %% Alice asks for Bob's private data
                          IQ = escalus_stanza:to(escalus_stanza:private_set(my_banana(NS)), bob),
                          escalus_client:send(Alice, IQ),

                          %% Alice gets a forbidden error
                          Stanza = escalus_client:wait_for_stanza(Alice),
                          escalus:assert(is_private_error, Stanza),
                          escalus_pred:is_error(<<"cancel">>, forbidden, Stanza)
                  end).

missing_ns(Config) ->
    escalus:story(Config, [1],
                  fun(Alice) ->
                          %% Alice asks for her own private storage, without
                          %% providing a namespace for a child
                          MyBanana = #xmlelement{name = <<"my_element">>,
                                                 children = [#xmlelement{name = <<"banana">>}]},
                          IQ = escalus_stanza:private_get(MyBanana),
                          escalus_client:send(Alice, IQ),

                          %% Alice gets a bad-format error
                          Stanza = escalus_client:wait_for_stanza(Alice),
                          escalus:assert(is_private_error, Stanza),
                          escalus_pred:is_error(<<"modify">>, 'bad-format', Stanza)
                  end).

%%-----------------------------------------------------------------
%% Helpers
%%-----------------------------------------------------------------

my_banana(NS) ->
    #xmlelement{
        name = <<"my_element">>,
        attrs = [{<<"xmlns">>, NS}],
        children = [#xmlelement{name = <<"banana">>}]}.

check_body(Stanza, Names) ->
    Query = exml_query:subelement(Stanza, <<"query">>),
    check_body_rec(Query, Names).

check_body_rec(_, []) ->
    ok;
check_body_rec(Element, [Name | Names]) ->
    [Child] = Element#xmlelement.children,
    Name = Child#xmlelement.name,
    check_body_rec(Child, Names).