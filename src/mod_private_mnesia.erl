%%%-------------------------------------------------------------------
%%% @author Evgeny Khramtsov <ekhramtsov@process-one.net>
%%% @copyright (C) 2016, Evgeny Khramtsov
%%% @doc
%%%
%%% @end
%%% Created : 13 Apr 2016 by Evgeny Khramtsov <ekhramtsov@process-one.net>
%%%-------------------------------------------------------------------
-module(mod_private_mnesia).
-behaviour(mod_private).

%% API
-export([init/2, set_data/3, get_data/3, get_all_data/2, remove_user/2,
	 import/2]).

-include("jlib.hrl").
-include("mod_private.hrl").
-include("logger.hrl").

%%%===================================================================
%%% API
%%%===================================================================
init(_Host, _Opts) ->
    mnesia:create_table(private_storage,
			[{disc_only_copies, [node()]},
			 {attributes,
			  record_info(fields, private_storage)}]),
    update_table().

set_data(LUser, LServer, Data) ->
    F = fun () ->
		lists:foreach(
		  fun({XmlNS, Xmlel}) ->
			  mnesia:write(
			    #private_storage{
			       usns = {LUser, LServer, XmlNS},
			       xml = Xmlel})
		  end, Data)
	end,
    mnesia:transaction(F).

get_data(LUser, LServer, XmlNS) ->
    case mnesia:dirty_read(private_storage, {LUser, LServer, XmlNS}) of
	[#private_storage{xml = Storage_Xmlel}] ->
	    {ok, Storage_Xmlel};
	_ ->
	    error
    end.

get_all_data(LUser, LServer) ->
    lists:flatten(
      mnesia:dirty_select(private_storage,
                          [{#private_storage{usns = {LUser, LServer, '_'},
                                             xml = '$1'},
                            [], ['$1']}])).

remove_user(LUser, LServer) ->
    F = fun () ->
		Namespaces = mnesia:select(private_storage,
					   [{#private_storage{usns =
								  {LUser,
								   LServer,
								   '$1'},
							      _ = '_'},
					     [], ['$$']}]),
		lists:foreach(fun ([Namespace]) ->
				      mnesia:delete({private_storage,
						     {LUser, LServer,
						      Namespace}})
			      end,
			      Namespaces)
	end,
    mnesia:transaction(F).

import(_LServer, #private_storage{} = PS) ->
    mnesia:dirty_write(PS).

%%%===================================================================
%%% Internal functions
%%%===================================================================
update_table() ->
    Fields = record_info(fields, private_storage),
    case mnesia:table_info(private_storage, attributes) of
      Fields ->
          ejabberd_config:convert_table_to_binary(
            private_storage, Fields, set,
            fun(#private_storage{usns = {U, _, _}}) -> U end,
            fun(#private_storage{usns = {U, S, NS}, xml = El} = R) ->
                    R#private_storage{usns = {iolist_to_binary(U),
                                              iolist_to_binary(S),
                                              iolist_to_binary(NS)},
                                      xml = fxml:to_xmlel(El)}
            end);
      _ ->
	  ?INFO_MSG("Recreating private_storage table", []),
	  mnesia:transform_table(private_storage, ignore, Fields)
    end.
