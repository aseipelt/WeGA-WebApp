xquery version "3.0" encoding "UTF-8";

(:~
 : WeGA facets XQuery-Modul
 :
 : @author Peter Stadler 
 : @version 2.0
 :)

module namespace facets="http://xquery.weber-gesamtausgabe.de/modules/facets";
declare default collation "?lang=de;strength=primary";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace mei="http://www.music-encoding.org/ns/mei";
declare namespace xhtml="http://www.w3.org/1999/xhtml";
declare namespace exist="http://exist.sourceforge.net/NS/exist";
declare namespace session = "http://exist-db.org/xquery/session";
declare namespace util = "http://exist-db.org/xquery/util";
declare namespace templates="http://exist-db.org/xquery/templates";
import module namespace config="http://xquery.weber-gesamtausgabe.de/modules/config" at "config.xqm";
import module namespace core="http://xquery.weber-gesamtausgabe.de/modules/core" at "core.xqm";
import module namespace norm="http://xquery.weber-gesamtausgabe.de/modules/norm" at "norm.xqm";
import module namespace lang="http://xquery.weber-gesamtausgabe.de/modules/lang" at "lang.xqm";
import module namespace query="http://xquery.weber-gesamtausgabe.de/modules/query" at "query.xqm";
import module namespace str="http://xquery.weber-gesamtausgabe.de/modules/str" at "str.xqm";
import module namespace functx="http://www.functx.com";

declare 
    %templates:default("lang", "en")
    function facets:select($node as node(), $model as map(*), $lang as xs:string) as element(select) {
        let $facet := $node/data(@name)
        let $facet-items := 
            switch($facet)
            case 'textType' return facets:from-docType($model('search-results'), $facet, $lang)
            default return facets:from-index($model('search-results'), $facet)
        return
            element {name($node)} {
                $node/@*,
                element option {
                    (:if(map:contains($model('filters'), $facet)) then ()
                    else attribute selected {'selected'},:)
                    attribute value {''},
                    lang:get-language-string('all', $lang)
                },
                $facet-items ! 
                    element option {
                        if(map:get($model('filters'), $facet) = ./facets:value) then 
                            attribute selected {'selected'}
                        else (),
                        attribute value {./facets:value},
                        ./facets:term || ' (' || ./facets:frequency || ')'
                    }
            }
};

declare %private function facets:from-index($collection as node()*, $facet as xs:string) as element(facets:entry)* {
    let $index-entries := facets:index-entries($collection, $facet)
(:    let $startTime := util:system-time():)
    return (
        facets:createFacets($index-entries)(:,
        util:log-system-out($facet || ': ' || string(seconds-from-duration(util:system-time() - $startTime))):)
    )
};

declare %private function facets:from-docType($collection as node()*, $facet as xs:string, $lang as xs:string) as element(facets:entry)* {
    for $i in $collection
    group by $docType := substring($i/*/@xml:id, 1, 3)
    return 
        <facets:entry>
            <facets:term>{lang:get-language-string($config:wega-docTypes-inverse($docType), $lang)}</facets:term>
            <facets:value>{$config:wega-docTypes-inverse($docType)}</facets:value>
            <facets:frequency>{count($i)}</facets:frequency>
        </facets:entry>
};

(:~
 : Returns list of terms and their frequency in the collection
 :
 : @author Peter Stadler 
 : @param $term
 : @param $data contains frequency
 : @return element
 :)
declare %private function facets:term-callback($term as xs:string, $data as xs:int+) as element(facets:entry)? {
    <facets:entry>
        <facets:term>{
            switch(config:get-doctype-by-id($term))
            case 'persons' return query:get-reg-name($term)
            case 'works' return query:get-reg-title($term)
            default return str:normalize-space($term) 
        }</facets:term>
        <facets:value>{str:normalize-space($term)}</facets:value>
        <facets:frequency>{$data[2]}</facets:frequency>
    </facets:entry>
};

(:~
 : Create facets
 :
 : @author Peter Stadler 
 : @param $collFacets
 : @return element
 :)
declare %private function facets:createFacets($collFacets as item()*) as element(facets:entry)* {
    for $k in util:index-keys($collFacets, '', facets:term-callback#2, -1)
(:        order by $k//xs:int(facets:frequency) descending:)
        order by $k//facets:term ascending
        return $k
};

declare %private function facets:index-entries($collection as node()*, $facet as xs:string) as item()* {
    switch($facet)
    case 'sender' return $collection//@key[ancestor::tei:sender]
    case 'addressee' return $collection//@key[ancestor::tei:addressee]
    case 'docStatus' return $collection/*/@status | $collection//tei:revisionDesc/@status
    case 'placeOfSender' return $collection//tei:placeName[parent::tei:placeSender]
    case 'placeOfAddressee' return $collection//tei:placeName[parent::tei:placeAddressee]
    case 'journals' return $collection//tei:title[@level='j'][not(@type='sub')][ancestor::tei:sourceDesc]
    case 'places' return $collection//tei:settlement[ancestor::tei:text or ancestor::tei:ab]
    case 'dedicatees' return $collection//mei:persName[@role='dte']/@dbkey
    case 'lyricists' return $collection//mei:persName[@role='lyr']/@dbkey
    case 'librettists' return $collection//mei:persName[@role='lbt']/@dbkey
    case 'composers' return $collection//mei:persName[@role='cmp']/@dbkey
    case 'docSource' return $collection/tei:person/@source
    case 'occupations' return $collection//tei:occupation
    case 'residences' return $collection//tei:settlement[parent::tei:residence]
        (: index-keys does not work with multiple whitespace separated keys
            probably need to change to ft:query() someday?!
        :)
    case 'persons' return ($collection//tei:persName[ancestor::tei:text or ancestor::tei:ab]/@key | $collection//tei:rs[@type='person'][ancestor::tei:text or ancestor::tei:ab]/@key[matches(., '^A02\d{4}$')])
    case 'works' return ($collection//@key[parent::tei:workName][matches(., '^A02\d{4}$')] | $collection//@key[parent::tei:rs/@type='work'][matches(., '^A02\d{4}$')])
    case 'authors' return $collection//tei:author/@key
    case 'editors' return $collection//tei:editor/@key
    case 'biblioType' return $collection/tei:biblStruct/@type
    default return ()
};

declare 
    %templates:default("lang", "en") 
    %templates:wrap
    function facets:document-allFilter($node as node(), $model as map(*), $lang as xs:string) as map(*) {
        map {
            'filterSections' := 
                for $filter in ('persons', 'works')
                let $keys := distinct-values($model('doc')//@key[ancestor::tei:text or ancestor::tei:ab]/tokenize(., '\s+')[starts-with(., $config:wega-docTypes($filter))])
                return 
                    if(exists($keys)) then map { $filter := $keys}
                    else ()
        }
};

declare 
    %templates:default("lang", "en")
    %templates:wrap
    function facets:filter-options($node as node(), $model as map(*), $lang as xs:string) as map(*) {
        map {
            'filterOptions' := 
                (: iterating over filterSection although there's only one key in this map :)
                for $i in map:keys($model('filterSection'))
                    for $j in $model('filterSection')($i)
                    let $label :=
                        switch($i)
                        case 'persons' return query:get-reg-name($j)
                        default return query:get-reg-title($j)
                    order by $label ascending
                    return map { 'key' := $j, 'label' := $label}
        }
};

declare function facets:filter-body($node as node(), $model as map(*)) as element(div) {
    element {name($node)} {
        $node/@class,
        (: That should be safe because there's always only one key in filterSection :)
        attribute id {map:keys($model('filterSection'))},
        templates:process($node/node(), $model)
    }
};

declare 
    %templates:default("lang", "en") 
    function facets:filter-head($node as node(), $model as map(*), $lang as xs:string) as element(h2) {
        element {name($node)} {
            $node/@*[not(name(.) = 'href')],
            (: That should be safe because there's always only one key in filterSection :)
            attribute href {'#' || map:keys($model('filterSection'))},
            lang:get-language-string(map:keys($model('filterSection')), $lang)
        }
};

declare function facets:filter-value($node as node(), $model as map(*)) as element(input) {
    element {name($node)} {
        $node/@*[not(name(.) = 'id')],
        attribute value {$model('filterOption')('key')}
    }
};

declare function facets:filter-label($node as node(), $model as map(*)) as xs:string {
    $model('filterOption')('label')
};
