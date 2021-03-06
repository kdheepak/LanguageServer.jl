JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWatchedFiles")}}, params) = DidChangeWatchedFilesParams(params)
function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWatchedFiles")},DidChangeWatchedFilesParams}, server)
    for change in r.params.changes
        uri = change.uri
        !haskey(server.documents, URI2(uri)) && continue
        if change.type == FileChangeTypes["Created"] || (change.type == FileChangeTypes["Changed"] && !get_open_in_editor(server.documents[URI2(uri)]))
            doc = server.documents[URI2(uri)]
            filepath = uri2filepath(uri)
            content = String(read(filepath))
            content == get_text(doc) && return
            server.documents[URI2(uri)] = Document(uri, content, true, server)
            parse_all(server.documents[URI2(uri)], server)

        elseif change.type == FileChangeTypes["Deleted"] && !get_open_in_editor(server.documents[URI2(uri)])
            delete!(server.documents, URI2(uri))

            response =  JSONRPC.Request{Val{Symbol("textDocument/publishDiagnostics")},PublishDiagnosticsParams}(nothing, PublishDiagnosticsParams(uri, Diagnostic[]))
            send(response, server)
        end
    end
end


JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeConfiguration")}}, params) = params
function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeConfiguration")},Dict{String,Any}}, server::LanguageServerInstance)
    send(JSONRPC.Request{Val{Symbol("workspace/configuration")},ConfigurationParams}(-100, ConfigurationParams([
        (ConfigurationItem(missing, "julia.format.$opt") for opt in fieldnames(DocumentFormat.FormatOptions))...;
        ConfigurationItem(missing, "julia.runLinter")
        ])), server)
end



JSONRPC.parse_params(::Type{Val{Symbol("workspace/didChangeWorkspaceFolders")}}, params) = didChangeWorkspaceFoldersParams(params)
function process(r::JSONRPC.Request{Val{Symbol("workspace/didChangeWorkspaceFolders")}}, server)
    for wksp in r.params.event.added
        push!(server.workspaceFolders, uri2filepath(wksp.uri))
        load_folder(wksp, server)
    end
    for wksp in r.params.event.removed
        delete!(server.workspaceFolders, uri2filepath(wksp.uri))
        remove_workspace_files(wksp, server)
    end
end


JSONRPC.parse_params(::Type{Val{Symbol("workspace/symbol")}}, params) = WorkspaceSymbolParams(params) 
function process(r::JSONRPC.Request{Val{Symbol("workspace/symbol")},WorkspaceSymbolParams}, server) 
    syms = SymbolInformation[]
    for (uri,doc) in server.documents
        bs = collect_toplevel_bindings_w_loc(getcst(doc), query = r.params.query)
        for x in bs
            p, b = x[1], x[2]
            push!(syms, SymbolInformation(valof(b.name), 1, false, Location(doc._uri, Range(doc, p)), nothing))
        end
    end

    response = JSONRPC.Response(r.id, syms) 
    send(response, server) 
end