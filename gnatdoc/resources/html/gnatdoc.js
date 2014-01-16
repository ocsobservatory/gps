
function buildText(root, data)
{
    var element;

    for (var index = 0; index < data.length; index++)
    {
        switch (data[index].kind)
        {
            case 'code':
                element = document.createElement('table');
                element.setAttribute('class', 'code');
                element.setAttribute('cellpadding', '0');
                element.setAttribute('cellspacing', '0');
                var code = document.createElement('tbody');

                for (lineIndex = 0;
                     lineIndex < data[index].children.length;
                     lineIndex++)
                {
                    var line = data[index].children[lineIndex];
                    var row = document.createElement('tr');
                    var cell = document.createElement('th');
                    cell.setAttribute('id', 'L' + line.number.toString());
                    cell.appendChild(document.createTextNode(line.number));
                    row.appendChild(cell);
                    cell = document.createElement('td');
                    buildText(cell, line.children);
                    row.appendChild(cell);
                    code.appendChild(row);
                }

                element.appendChild(code);
                break;

            case 'paragraph':
                element = document.createElement('p');
                buildText(element, data[index].children);
                break;

            case 'ul':
                element = document.createElement('ul');
                buildText(element, data[index].children);
                break;

            case 'li':
                element = document.createElement('li');
                buildText(element, data[index].children);
                break;

            case 'span':
                element = document.createElement('span');

                if (typeof data[index].href !== 'undefined')
                {
                    var href = document.createElement('a');
                    href.setAttribute('href', '../' + data[index].href);
                    href.appendChild(document.createTextNode(data[index].text));
                    element.appendChild(href);

                } else
                {
                    element.appendChild(
                      document.createTextNode(data[index].text));
                }

                if (typeof data[index].class !== 'undefined')
                {
                    element.setAttribute('class', data[index].class);
                }

                break;
        }
        root.appendChild(element);
    }
}

function buildDocumentationPage()
{
    var pane;
    var header;
    var text;
    var href;
    var sup;

    pane = document.getElementById('body');

    /* Build 'Summary' section */

    header = document.createElement('h1');
    text = document.createTextNode(GNATdocDocumentation.label);
    header.appendChild(text);
    pane.appendChild(header);
    buildText(pane, GNATdocDocumentation.summary);
    href = document.createElement('a');
    href.setAttribute('href', '#Description');
    text = document.createTextNode('More...');
    href.appendChild(text);
    pane.appendChild(href);

    /* Build 'Entities' section */

    header = document.createElement('h2');
    text = document.createTextNode('Entities');
    header.appendChild(text);
    pane.appendChild(header);

    for (var index = 0; index < GNATdocDocumentation.entities.length; index++)
    {
        var entity_set = GNATdocDocumentation.entities[index];
        var table;
        var tbody;

        header = document.createElement('h3');
        text = document.createTextNode(entity_set.label);
        header.appendChild(text);
        pane.appendChild(header);

        table = document.createElement('table');
        table.setAttribute('class', 'entities');
        table.setAttribute('cellpadding', '0');
        table.setAttribute('cellspacing', '0');
        tbody = document.createElement('tbody');

        for (var eindex = 0; eindex < entity_set.entities.length; eindex++)
        {
            var entity = entity_set.entities[eindex];
            var row;
            var cell;

            row = document.createElement('tr');
            cell = document.createElement('th');
            href = document.createElement('a');

            if (typeof entity.href !== 'undefined')
            {
                href.setAttribute('href', entity.href);
            } else {
                href.setAttribute(
                  'href',
                  '#L' + entity.line.toString() +
                  'C' + entity.column.toString());
            }

            href.appendChild(document.createTextNode(entity.label));
            cell.appendChild(href);
            row.appendChild(cell);
            cell = document.createElement('td');
            buildText(cell, entity.summary);
            row.appendChild(cell);
            tbody.appendChild(row);
        }

        table.appendChild(tbody);
        pane.appendChild(table);
    }

    /* Build 'Description' section */

    header = document.createElement('h2');
    header.setAttribute('id', 'Description');
    text = document.createTextNode('Description');
    header.appendChild(text);
    pane.appendChild(header);
    buildText(pane, GNATdocDocumentation.description);

    /* Build entities description sections */

    for (var index = 0; index < GNATdocDocumentation.entities.length; index++)
    {
        var entity_set = GNATdocDocumentation.entities[index];

        for (var eindex = 0; eindex < entity_set.entities.length; eindex++)
        {
            var list = null;
            var entity = entity_set.entities[eindex];

            if (typeof entity.href == 'undefined')
            {
                header = document.createElement('h3');
                header.setAttribute(
                  'id',
                  'L' + entity.line.toString() +
                  'C' + entity.column.toString());
                header.appendChild(document.createTextNode(entity.label));
                sup = document.createElement('sup');
                sup.setAttribute('class', 'srcHref');
                href = document.createElement('a');
                href.setAttribute(
                  'href',
                  '../' + entity.src +
                  '#L' + entity.line.toString());
                href.appendChild(document.createTextNode(' [source]'));
                sup.appendChild(href);
                header.appendChild(sup);
                pane.appendChild(header);
                buildText(pane, entity.description);

                if (typeof entity.inherits !== 'undefined')
                {
                    var paragraph = document.createElement('p');
                    paragraph.appendChild(document.createTextNode('Inherits '));

                    for (var iindex = 0;
                         iindex < entity.inherits.length;
                         iindex++)
                    {
                        if (iindex != 0)
                          paragraph.appendChild(document.createTextNode(', '));

                        if (typeof entity.inherits[iindex].docHref ==
                              'undefined')
                        {
                          paragraph.appendChild(
                            document.createTextNode(
                              entity.inherits[iindex].label));
                        }
                        else
                        {
                           href = document.createElement('a');
                           href.setAttribute(
                             'href', '../' + entity.inherits[iindex].docHref);
                           href.setAttribute('target', 'contentView');
                           href.appendChild(
                             document.createTextNode(
                               entity.inherits[iindex].label));
                           paragraph.appendChild(href);
                        }
                    }

                    pane.appendChild(paragraph);
                }

                if (typeof entity.inherited !== 'undefined')
                {
                    var paragraph = document.createElement('p');
                    paragraph.appendChild(
                      document.createTextNode('Inherited by '));

                    for (var iindex = 0;
                         iindex < entity.inherited.length;
                         iindex++)
                    {
                        if (iindex != 0)
                          paragraph.appendChild(document.createTextNode(', '));

                        href = document.createElement('a');
                        href.setAttribute(
                          'href', '../' + entity.inherited[iindex].docHref);
                        href.setAttribute('target', 'contentView');
                        href.appendChild(
                          document.createTextNode(
                            entity.inherited[iindex].label));
                        paragraph.appendChild(href);
                    }

                    pane.appendChild(paragraph);
                }

                if (typeof entity.parameters !== 'undefined')
                {
                    list = document.createElement('dl');

                    for (var pindex = 0;
                         pindex < entity.parameters.length;
                         pindex++)
                    {
                        var parameter = entity.parameters[pindex];
                        var term = document.createElement('dt');
                        term.setAttribute(
                          'id',
                          'L' + parameter.line.toString() +
                            'C' + parameter.column.toString());
                        term.appendChild(
                          document.createTextNode(parameter.label));
                        var description = document.createElement('dd');
                        buildText(description, parameter.description);

                        list.appendChild(term);
                        list.appendChild(description);
                    }
                }

                if (typeof entity.returns !== 'undefined')
                {
                    if (list == null) list = document.createElement('dl');

                    var term = document.createElement('dt');
                    term.appendChild(document.createTextNode('Return value'));
                    var description = document.createElement('dd');
                    buildText(description, entity.returns.description);

                    list.appendChild(term);
                    list.appendChild(description);
                }

                if (typeof entity.exceptions !== 'undefined')
                {
                    if (list == null) list = document.createElement('dl');

                    var term = document.createElement('dt');
                    term.appendChild(document.createTextNode('Exceptions'));
                    var description = document.createElement('dd');
                    buildText(description, entity.exceptions.description);

                    list.appendChild(term);
                    list.appendChild(description);
                }

                if (list != null) pane.appendChild(list);
            }
        }
    }
}

function buildPackagesIndex(toc)
{
    header = document.createElement('h1');
    text = document.createTextNode('Packages and Classes');
    header.appendChild(text);
    toc.appendChild(header);

    list = document.createElement('ul');
    toc.appendChild(list);

    for (index = 0; index < GNATdocDocumentationIndex.length; index++)
    {
        entry = GNATdocDocumentationIndex[index];

        item = document.createElement('li');
        href = document.createElement('a');
        href.setAttribute('href', entry.file);
        href.setAttribute('target', 'contentView');
        text = document.createTextNode(entry.label);
        href.appendChild(text);
        item.appendChild(href);
        list.appendChild(item);
    }
}

function buildEntitiesCategoriesIndex(toc)
{
    var header;
    var text;
    var list;

    header = document.createElement('h1');
    header.appendChild(document.createTextNode('Entities Index'));
    toc.appendChild(header);

    list = document.createElement('ul');

    for (var index = 0; index < GNATdocEntitiesCategoriesIndex.length; index++)
    {
        var item;
        var href;
        var entry = GNATdocEntitiesCategoriesIndex[index];

        item = document.createElement('li');
        href = document.createElement('a');
        href.setAttribute('href', entry.href);
        href.setAttribute('target', 'contentView');
        href.appendChild(document.createTextNode(entry.label));
        item.appendChild(href);
        list.appendChild(item);
    }

    toc.appendChild(list);
}

function buildSourcesIndex(toc)
{
    header = document.createElement('h1');
    text = document.createTextNode('Source Files');
    header.appendChild(text);
    toc.appendChild(header);
    list = document.createElement('ul');
    toc.appendChild(list);

    for (index = 0; index < GNATdocSourceFileIndex.length; index++)
    {
        source = GNATdocSourceFileIndex[index];

        item = document.createElement('li');
        href = document.createElement('a');
        href.setAttribute('href', source.srcHref);
        href.setAttribute('target', 'contentView');
        text = document.createTextNode(source.label);
        href.appendChild(text);
        item.appendChild(href);
        list.appendChild(item);
    }
}

function buildEntitiesCategoryPage()
{
    var header;
    var character;
    var list;
    var page = document.getElementById('body');

    header = document.createElement('h1');
    header.appendChild(document.createTextNode(GNATdocEntitiesCategory.label));
    page.appendChild(header);

    character = '';
    list = document.createElement('dl');

    for (var index = 0;
         index < GNATdocEntitiesCategory.entities.length;
         index++)
    {
        var item;
        var href;
        var entity = GNATdocEntitiesCategory.entities[index];

        if (character == '' || character != entity.label[0].toUpperCase())
        {
            character = entity.label[0].toUpperCase();
            item = document.createElement('dt');
            item.appendChild(document.createTextNode(character));
            list.appendChild(item);
        }

        item = document.createElement('dd');
        href = document.createElement('a');
        href.setAttribute('href', '../' + entity.docHref);
        href.appendChild(document.createTextNode(entity.label));
        item.appendChild(href);
        item.appendChild(document.createTextNode(' from '));
        href = document.createElement('a');
        href.setAttribute('href', '../' + entity.srcHref);
        href.appendChild(document.createTextNode(entity.declared));
        item.appendChild(href);
        list.appendChild(item);
    }

    page.appendChild(list);
}

function buildInheritanceIndex(page)
{
    function build(list, entities)
    {
        for (var index = 0; index < entities.length; index++)
        {
            var item = document.createElement('li');
            var href = document.createElement('a');
            href.setAttribute('href', entities[index].docHref);
            href.appendChild(document.createTextNode(entities[index].label));
            item.appendChild(href);

            if (typeof entities[index].inherited !== 'undefined')
            {
                var sublist = document.createElement('ul');
                build(sublist, entities[index].inherited);
                item.appendChild(sublist);
            }
            list.appendChild(item);
        }
    }

    var list = document.createElement('ul');

    build(list, GNATdocInheritanceIndex);
    page.appendChild(list);
}

function displaySource()
{
    var pane;
    var header;

    pane = document.getElementById('body');
    header = document.createElement('h1');
    header.appendChild(document.createTextNode(GNATdocSourceFile.label));
    pane.appendChild(header);
    buildText(pane, [GNATdocSourceFile]);
}

function onDocumentationLoad()
{
    buildDocumentationPage();

    /* Scroll view to requested element. */

    var url = document.URL;
    var index = url.indexOf('#');

    if (index >= 0)
    {
        var id = url.slice(index + 1, url.length);
        var element = document.getElementById(id);

        if (element)
        {
            element.scrollIntoView();
        }
    }
}

function onLoad()
{
    var toc = document.getElementById('tocView');

    buildPackagesIndex(toc);
    buildEntitiesCategoriesIndex(toc);

    var header = document.createElement('h1');
    var href = document.createElement('a');
    href.setAttribute('href', 'inheritance_index.html');
    href.setAttribute('target', 'contentView');
    href.appendChild(document.createTextNode('Inheritance Tree'));
    header.appendChild(href);
    toc.appendChild(header);

    buildSourcesIndex(toc);
}

function onSourceFileLoad()
{
    displaySource();

    /* Scroll view to requested element. */

    var url = document.URL;
    var index = url.indexOf('#');

    if (index >= 0)
    {
        var id = url.slice(index + 1, url.length);
        var element = document.getElementById(id);

        if (element)
        {
            element.scrollIntoView();
            element.classList.add('target');
        }
    }
}

function onInheritanceLoad()
{
    var page = document.getElementById('body');

    buildInheritanceIndex(page);
}

function onEntitiesCategoryLoad()
{
    buildEntitiesCategoryPage();
}