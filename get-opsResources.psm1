<# 

    Version 1.05
    Updated: 2019/11/15

#>



function Get-OpsResources {
<#
  .SYNOPSIS
    Get resource(s) matching name, Regular Expression for a name, resourceID(s), resourceKind(s), etc..

  .DESCRIPTION
    Get Resource(s) matching a specified name or regex of name, resourceID(s), etc.. Optionally, for each matched
    and returned Resource, include a list of resourceIds of all that object's Children or its Parents.

  .EXAMPLE
    Get-OpsResources -name "vRealize Operations Manager Self Monitoring"

    Get the logical object which vROps uses to represent itself (includes descendant objects for the cluster, nodes, services).

  .EXAMPLE
    Get-OpsResources -regex ".*[Ss]elf [Mm]onitor.*"

    Get any objects whose name includes "Self Monitor" or "self monitor" or "self Monitor" or "Self monitor".
    NOTE: Put ".*" in front and back to get a match on part of the string. Without this, vROps will
    not match if there are other characters before or after your regex. ".*" means "zero or more of any character" (it's
    a wildcard in RegEx).

#>

    [cmdletbinding()]Param(
        
        # Hostname (FQDN) of the vROps cluster. NOT the full URL (no https://...).
        [string]
        $Server = $server,

        # The text of a token which can be used for authentication to vROps. Incompatible with Credential and with Username or Password.
        [parameter(Mandatory=$false)]
        [string]
        $AuthToken = $AuthToken,


        # Format in which you wish to get output. Either 'json' or 'xml'. Default: 'json'.
        [parameter(Mandatory=$false)]
        [ValidateSet('json','xml')]
        [string] 
        $FormatOut = 'json',

        # (optional) Location to which to write the retrieved data as a file.
        [parameter(Mandatory=$false)]
        [string]
        $Outfile,

        <# 
            (optional) "Expected number of entries per page." If specified, only up to this many will be returned. See also Page.
            Examples: 
                PageSize:7 ==> the first 7 items will be returned (#1-7)
                PageSize:3  ==> the first 3 items will be returned (#1-3)
                PageSize:3 ; Page:0 ==> first 3 items will be returned (#1-3)
                PageSize:3 ; Page:1 ==> second 3 items will be returned (#4-6)


        #> 
        [parameter(Mandatory=$false)]
        [int]
        $pageSize,

        <# 
            (optional) Starts counting at 0. Display only the entries on this "page", based on pagesize. 
            E.g. if Page is 0 and PageSize is 4, displays first 4 matching items (#1-4). 
            If Page is 1 and PageSize is 4, displays the second 4 matching items (#5-8)
        #>
        [parameter(Mandatory=$false)]
        [int]
        $page,


        # ------ identical-named parameters here and in API

        # Name of the resource.
        $name,

        # Regular Expression matching name of the resource. NOTE: vROps will NOT match a part of the string; the whole
        # name has to match this RegEx. So put ".*" before and after as a regex wildcard. E.g. if you make regex "Monitor",
        # you will not get the object named "vRealize Operations Manager Self Monitoring". Say ".*Monitor.*" instead.
        # Match is case-sensitive. If not sure, say like ".*onitor.*" or ".*[Mm]onitor.*"
        $regex,

        
        # This parameter in the getResources API call is exclusive with the resourceID.
        # Array of resourceKindKeys e.g. ("VirtualMachine","HostSystem")
        $resourceKind,

        # Array of adapterKindKeys
        $AdapterKind,

        # A non-null value specifies to include related resource ids of given relationship type in resource result. Allowed values are: PARENT, CHILD.
        [ValidateSet('PARENT','CHILD')]
        $includeRelated,

        # Array of resource identifiers
        $resourceId


      
    )

    <# TODO
        [] TEST how this works if you specify a parent and also -resourceKind
    #>

    # ----- define what are the identical names of parameters in both this function and the vROps REST API call
    $QueryAndFunctionIdenticalParameterNames = @("name","regex","resourceKind","adapterKind","includeRelated","resourceId")

    # ----- Validate we have required supporting functions -----
    $RequiredCommands = @()
    $RequiredCommands += 'Add-QueryParamsToString'
    $RequiredCommands += 'New-QueryParams'
    $RequiredCommands += 'New-IRMCommand'
    $MissingCommands = @()
    $RequiredCommands | Foreach-Object { 
        if ( ! (Get-Command $_ -ErrorAction SilentlyContinue) ) { $MissingCommands += $_ } 
    }
    if ( $MissingCommands ) {
        $ErrMsg = "You are missing some required commands. Make sure to load these commands into memory e.g. by dot-sourcing the files which define those functions. `nMissing Commands: `n$($MissingCommands | Format-List | Out-String)"
        Throw $ErrMsg
    }


    $Method = 'GET'
    $CmdURL = '/api/resources'
    $URL = "https://$($Server)/suite-api" + $CmdURL



    # ----- Validate parameter input -----
    # authentication 
    if ( ! $authtoken  ) {
        throw {"You must specify an authenticationtoken."}
    } 



    # ----- Make Headers -----
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

    Write-Verbose "$(get-date) Setting header asking for reply in desired format of $($FormatOut)."
    $headers.Add("Accept", "application/$($FormatOut)")

    Write-Verbose "$(get-date) Setting header specifying authentication to use."
    if ( $authToken ) {
    
        $headers.Add("Authorization", "vRealizeOpsToken $($authToken)")
    
    } 



    # ---- If the REST call is to have Query Parameters, build the QueryString and add it to the URL.
    $QueryString = "" # Make sure this is null before calling Add-QueryParamsToString the first time
    $QueryParams = New-QueryParams $QueryAndFunctionIdenticalParameterNames
    $QueryString = Add-QueryParamsToString -QueryString $QueryString -Params $QueryParams

    # Add QueryString to URL
    $URL = $URL + $QueryString
    Write-debug "$(get-date) URL including parameters: $($URL)"



    # ----- Build Body of request -----
    $body = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

    if ($page) { $body.add('page',$page) }

    if ($pageSize) { $body.add('pageSize',$pageSize ) }


    Write-Verbose "$(get-date) Body of request: $($Body | Out-String)"


    $QueryResult = Invoke-Expression ( New-IRMcommand )

    $QueryResult.resourceList

}

Export-ModuleMember Get-OpsResources




# ---- Supporting functions for REST API calls. Usually called only by code (not directly by users).

function Add-QueryParamsToString {
<#
  .SYNOPSIS
    For REST APIs, build up the string for all Query parameters. Pass in any existing query string, and one or more parameter key value pairs.
    
  .EXAMPLE
    $newQueryString = Add-QueryParamsToString -QueryString $currentQueryString -Params $KVpairs




#>


    [cmdletbinding()]Param(

        # The current QueryString, if any. New parameters will be appended to this.
        $QueryString,

        <# 
            One or more objects, each of which is a hashtable or one or more key-value pairs. 
            NOTE: some query parameters could be duplicated, so this should be an array of hashes, not just a single hashtable. 
            One hashtable can have a particular key appear only once, so you can have only one value for the key "id", 
            but if you want multiple id=____ pairs, you need multiple hashtables.
        #>
        $Params
        

    )

    If ( ! $QueryString ) {
        $QueryString = "?"
    }


    foreach ($param in $params) {
        # Each $param could actually be a set of multiple key-value pairs
        $param.Keys | Foreach {
            $thisKey = $_
            $thisValue = $param.$_ 
            Write-debug "$(get-date) key value pair: { `"$($thisKey)`" : `"$($thisValue)`"}"
            if ( $querystring -eq "?" ) {
                #$QueryString += '"' + $thisKey + '"' + '=' + '"'+ $thisValue + '"'
                $QueryString += $thisKey + '=' + $thisValue 
            } else {
                #$QueryString += '&' + '"' + $thisKey + '"' + '=' + '"'+ $thisValue + '"'
                $QueryString += '&' + $thisKey + '=' + $thisValue
            }
        }        
    }

    write-debug "$(get-date) QueryString is now: $($querystring)"
    return $QueryString


}

function New-QueryParams {
<#
  .SYNOPSIS
    Given a list of query parameter names, build the data structure needed by the function Add-QueryParamsToString.
  .DESCRIPTION
    The Add-QueryParamsToString function is used to construct the query string to add to a URL for a REST API call
    which uses query-style parameters.
    Add-QueryParamsToString needs an input: an array of key-value pairs.
    This function builds that input, for whatever parameter names have values specified.
#>

    [cmdletbinding()]Param(
        # The list of parameter names. Just the strings. E.g. ('resourceKindKey','adapterKindKey').
        # For any of those, if they have values, those key-value pairs will be returned in a list.
        # Any parameter name that does not have a value will not be included. Ex. if you
        # specify input as ('resourceKindKey','adapterKindKey'), but there is nothing stored in $adapaterKindKey,
        # the adapterKindKey will not be included in the return.
        $ParamNames
    )

    $QueryParams = @()

    $ParamNames | %{
        # Process each parameter name
        $paramName = $_ 
        if (  Invoke-Expression ('$' + $paramName)  ) {
            # Process only if at least one value has been supplied for the parameter

            $paramName | %{
        
                Invoke-Expression ('$' + $paramName) | Foreach {
                    # Process each value supplied for the parameter

                    $oneValueOfThisParam = $_
                    $QueryParams += @{"$paramName"=$oneValueOfThisParam}
                    <#
                        Example values after processing one $paramName:
                            $paramName: "resourceKind"  # string
                            $resourceKind: @("VirtualMachine","HostSystem") # array of strings
                            $QueryParams: @(  @{"resourceKind"="VirtualMachine"}, @{"resourceKind"="HostSystem"}  )  # array of one-entry hashtables
                    #>
                }
            }
        }
    }

    $QueryParams

}

function New-IRMcommand {
<#
  .synopsis
    Build the Invoke-RestMethod command string including any relevant arguments.

  .description
    Build the Invoke-RestMethod command string with any relevant arguments. Return this string, which can
    then be executed by Invoke-Expression.
    
  .example
    Invoke-Expression ( New-IRMcommand -method $method -url $url -headers $headers -credential $credential -body $body -outfile $outfile )

  .example
     Invoke-Expression ( New-IRMcommand )

     Same as above, but automatically and implicitly passes in whatever values are currently set for $method, $url, $headers, $credential, $body, $outfile.
     In some cases, not all those parameters will be used. Leaving it implicit means you do not have to know which ones have values and which don't.
     E.g. if I have a value for $credential, it will be passed in, but if I don't, I don't need to worry about it.

#>
   [cmdletbinding()]Param(
        $method = $method,
        $URL = $url,
        $headers = $headers,
        $credential = $credential,
        $body = $body,
        $outfile = $outfile
    )
    #In Param(), "$method = $method" is to allow implicitly inheriting value if $method is set in parent which invokes this


    $IRMcommand = "Invoke-RestMethod" + ( New-IRMargs -method $method -url $url -headers $headers -credential $credential -body $body -outfile $outfile )
    $IRMcommand
}

function New-IRMargs {
<#
  .synopsis
    Build the arguments for the Invoke-RestMethod command
#>

    [cmdletbinding()]Param(
        $method = $method,
        $URL = $url,
        $headers = $headers,
        $credential = $credential,
        $body = $body,
        $outfile = $outfile
    )
    #In Param(), "$method = $method" is to allow implicitly inheriting value if $method is set in parent which invokes this, etc..

    $IRMarguments = ""

    if ($Method) {
        $IRMarguments += ' -Method $Method'
        Write-Debug "$(get-date) Adding to arguments Method: $($method)"
    } else { 
        Throw "No basic REST Method specified (GET, PUT, POST, etc.)." 
    }
    
    if ($URL) {
        $IRMarguments += ' -Uri $URL'
        Write-Debug "$(get-date) Adding to arguments Uri: $($URL)"
    } else { 
        Throw "No URL specified for REST call." 
    }
    
    if ($Headers) {
        $IRMarguments += ' -Headers $Headers'
        Write-Debug "$(get-date) Adding to arguments Headers: $($Headers | Out-String)"
        # Beware this may contain authorization info in plain text

    }
    
    if ($Credential) {
        $IRMarguments += ' -Credential $Credential'
        Write-Debug "$(get-date) Adding to arguments Credential: $($Credential | Out-String)"
        # Beware this may contain authorization info in plain text

    }
    
    if ($Body) {
        $IRMarguments += ' -Body $Body'
        Write-Debug "$(get-date) Adding to arguments Body: $($Body | Out-String)"

    }
    
    if ($Outfile) {
        $IRMarguments += ' -OutFile $Outfile'
        Write-Debug "$(get-date) Adding to arguments OutFile: $($OutFile)"

    }

    $IRMarguments

}




