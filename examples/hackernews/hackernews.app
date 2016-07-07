<app:app xmlns:app="http://etl.dob.sk/app"
		xmlns:etl="http://etl.dob.sk/etl"
		xmlns:embed="http:/etl.dob.sk/embed"
		xmlns:tr="http://etl.dob.sk/transform">
<!-- file paths -->
<!-- <app:file-path>lib</app:file-path> -->
<!-- request -->
<app:req>
	<tr:transform stylesheet="xslt:embed://hackernews.xsl">
		<http:req method="get" etl:cache="15 minutes" xmlns:http="http://etl.dob.sk/http">
			<http:url>https://news.ycombinator.com/</http:url>
		</http:req>
	</tr:transform>
</app:req>

<!-- stylesheet -->
<embed:embed id="hackernews.xsl" xmlns:embed="http://etl.dob.sk/embed">
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
				xmlns:etl="http://etl.dob.sk/etl"
				xmlns:str="http://exslt.org/strings"
				xmlns:date="http://exslt.org/dates-and-times"
				xmlns:xhtml="http://www.w3.org/1999/xhtml"
				xmlns:db="http://etl.dob.sk/dmlquery"
				extension-element-prefixes="str date"
				exclude-result-prefixes="xhtml">
<xsl:output method="xml" indent="no" encoding="utf-8" cdata-section-elements="url"/>

<xsl:template match="/">
<links>
	<xsl:apply-templates select="//xhtml:table/xhtml:tr[@class = 'athing']"/>
</links>
</xsl:template>

<xsl:template match="xhtml:tr">
<xsl:variable name="url" select="descendant::xhtml:a[@class = 'storylink']/@href"/>
<link rank="{substring-before(xhtml:td/xhtml:span[@class = 'rank'], '.')}">
	<title url="{$url}"><xsl:value-of select="normalize-space(descendant::xhtml:a[@class = 'storylink'])"/></title>
	<site><xsl:value-of select="descendant::xhtml:a[@class = 'storylink']/following-sibling::xhtml:span/xhtml:a/xhtml:span"/></site>
</link>
</xsl:template>

</xsl:stylesheet>
</embed:embed>

</app:app>
